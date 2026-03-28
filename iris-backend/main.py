from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
import anthropic
import asyncio
import base64
import httpx
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI()

ELEVENLABS_API_KEY = os.environ.get('ELEVENLABS_API_KEY')
ANTHROPIC_API_KEY = os.environ.get('ANTHROPIC_API_KEY')

# State machine - tracks the current experiment
state = {
    "current_step": 0,
    "steps": []
}

# Request body model
class ExperimentRequest(BaseModel):
    experiment_type: str

@app.get("/")
def root():
    return {"message": "Iris backend is running"}

@app.post("/start-experiment")
def start_experiment(request: ExperimentRequest):
    
    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
    
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        messages=[
            {
                "role": "user",
                "content": f"List the step-by-step instructions for a {request.experiment_type} experiment in a science lab. Return ONLY a numbered list of steps, nothing else. Keep each step short and clear, maximum 10 words per step."
            }
        ]
    )
    
    raw_text = message.content[0].text
    lines = raw_text.strip().split("\n")
    steps = [line.strip() for line in lines if line.strip()]
    
    state["steps"] = steps
    state["current_step"] = 0
    
    return {
        "success": True,
        "experiment_type": request.experiment_type,
        "steps": steps,
        "current_step": 0
    }

@app.get("/current-step")
def get_current_step():
    if not state["steps"]:
        return {"error": "No experiment started"}
    
    return {
        "step_number": state["current_step"],
        "instruction": state["steps"][state["current_step"]],
        "total_steps": len(state["steps"])
    }

@app.post("/advance-step")
def advance_step():
    if not state["steps"]:
        return {"error": "No experiment started"}
    
    if state["current_step"] < len(state["steps"]) - 1:
        state["current_step"] += 1
        return {
            "success": True,
            "current_step": state["current_step"],
            "instruction": state["steps"][state["current_step"]]
        }
    else:
        return {
            "success": False,
            "message": "Already on last step"
        }

@app.websocket("/experiment-stream")
async def experiment_stream(websocket: WebSocket):
    await websocket.accept()
    
    alternating_flag = True
    # Minimal 1x1 solid black JPEG byte array as a fake camera frame placeholder
    fake_camera_frame = b'\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c $.\' ",#\x1c\x1c(7),01444\x1f\'9=82<.342\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00\xff\xc4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xc4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xda\x00\x08\x01\x01\x00\x00?\x00\xd2\xff\xd9'

    try:
        async with httpx.AsyncClient() as client:
            while True:
                if alternating_flag:
                    text_to_say = "Correct, please continue to the next step"
                else:
                    text_to_say = "Stop, that is the wrong beaker, please use Flask A"
                
                alternating_flag = not alternating_flag
                
                tts_url = "https://api.elevenlabs.io/v1/text-to-speech/gJx1vCzNCD1EQHT212Ls"
                headers = {
                    "Accept": "audio/mpeg",
                    "Content-Type": "application/json",
                    "xi-api-key": ELEVENLABS_API_KEY
                }
                data = {
                    "text": text_to_say,
                    "model_id": "eleven_flash_v2_5"
                }
                
                response = await client.post(tts_url, json=data, headers=headers)
                
                if response.status_code == 200:
                    audio_bytes = response.content
                    audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
                    
                    # Sending as a JSON object so the client can also get the text.
                    # If you need just the raw string, it would be await websocket.send_text(audio_b64)
                    await websocket.send_json({
                        "audio_base64": audio_b64,
                        "text": text_to_say
                    })
                else:
                    print(f"ElevenLabs API Error: {response.text}")
                
                # Wait 500ms before the next loop
                await asyncio.sleep(0.5)
                
    except WebSocketDisconnect:
        print("Client disconnected from /experiment-stream")
    except Exception as e:
        print(f"WebSocket error: {e}")