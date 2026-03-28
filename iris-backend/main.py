from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
import anthropic
import asyncio
import base64
import httpx
import os
from dotenv import load_dotenv

import aiohttp
import cv2
import numpy as np
import overshoot

load_dotenv()

app = FastAPI()

ELEVENLABS_API_KEY = os.environ.get('ELEVENLABS_API_KEY')
ANTHROPIC_API_KEY = os.environ.get('ANTHROPIC_API_KEY')
ESP32_CAPTURE_URL = os.environ.get("ESP32_CAPTURE_URL", "http://192.168.137.5/capture")
OVERSHOOT_API_KEY = os.environ.get("OVERSHOOT_APIKEY")

# State machine - tracks the current experiment
state = {
    "current_step": 0,
    "steps": [],
    "experiment_type": ""
}

# Request body model
class ExperimentRequest(BaseModel):
    experiment_type: str

class AskQuestionRequest(BaseModel):
    question: str

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
    state["experiment_type"] = request.experiment_type
    
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

@app.post("/ask-question")
async def ask_question(request: AskQuestionRequest):
    if not state["steps"]:
        return {"error": "No experiment started"}
        
    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
    
    prompt = f"You are a lab assistant helping a student with a {state['experiment_type']} experiment. They are currently on this step: {state['steps'][state['current_step']]}. The student asks: {request.question}. Answer in 2-3 sentences maximum. Be clear, helpful and simple \u2014 your response will be read aloud to the student."
    
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=256,
        messages=[
            {
                "role": "user",
                "content": prompt
            }
        ]
    )
    
    answer_text = message.content[0].text
    
    tts_url = "https://api.elevenlabs.io/v1/text-to-speech/gJx1vCzNCD1EQHT212Ls"
    headers = {
        "Accept": "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": ELEVENLABS_API_KEY
    }
    data = {
        "text": answer_text,
        "model_id": "eleven_flash_v2_5"
    }
    
    async with httpx.AsyncClient() as httpx_client:
        response = await httpx_client.post(tts_url, json=data, headers=headers)
        
    if response.status_code == 200:
        audio_b64 = base64.b64encode(response.content).decode('utf-8')
        return {
            "answer_text": answer_text,
            "audio_base64": audio_b64
        }
    else:
        return {
            "error": f"ElevenLabs API Error: {response.text}"
        }

@app.post("/end-experiment")
async def end_experiment():
    if not state["experiment_type"]:
        return {"error": "No experiment started"}

    experiment_type = state["experiment_type"]
    steps = state["steps"]
    total_steps = len(steps)
    current_step = state["current_step"]

    prompt = f"You are a lab assistant. A student just completed a {experiment_type} experiment. \nThey completed {current_step + 1} out of {total_steps} steps.\nHere were the steps: {steps}\n\nWrite a short 3-4 sentence summary of what the student accomplished today. \nMention what scientific concept they practiced, what they should have observed, \nand one encouraging sentence. Keep it simple — it will be read aloud to the student."

    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
    
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=300,
        messages=[
            {
                "role": "user",
                "content": prompt
            }
        ]
    )
    
    summary_text = message.content[0].text
    
    tts_url = "https://api.elevenlabs.io/v1/text-to-speech/gJx1vCzNCD1EQHT212Ls"
    headers = {
        "Accept": "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": ELEVENLABS_API_KEY
    }
    data = {
        "text": summary_text,
        "model_id": "eleven_flash_v2_5"
    }
    
    async with httpx.AsyncClient() as httpx_client:
        response = await httpx_client.post(tts_url, json=data, headers=headers)
        
    if response.status_code == 200:
        audio_b64 = base64.b64encode(response.content).decode('utf-8')
        
        # Reset state back to empty
        state["current_step"] = 0
        state["steps"] = []
        state["experiment_type"] = ""
        
        return {
            "summary_text": summary_text,
            "audio_base64": audio_b64,
            "steps_completed": current_step + 1,
            "total_steps": total_steps
        }
    else:
        return {
            "error": f"ElevenLabs API Error: {response.text}"
        }

async def fetch_frame(session: aiohttp.ClientSession):
    try:
        async with session.get(ESP32_CAPTURE_URL, timeout=aiohttp.ClientTimeout(total=5)) as resp:
            if resp.status != 200:
                return None
            jpeg = await resp.read()
            if not jpeg:
                return None
    except Exception:
        return None
    bgr = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_COLOR)
    if bgr is None:
        return None
    bgr = cv2.resize(bgr, (800, 600), interpolation=cv2.INTER_LINEAR)
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    rgba = cv2.cvtColor(rgb, cv2.COLOR_RGB2RGBA)
    return np.ascontiguousarray(rgba)

@app.websocket("/experiment-stream")
async def experiment_stream(websocket: WebSocket):
    await websocket.accept()
    
    client = overshoot.Overshoot(api_key=OVERSHOOT_API_KEY)
    source = overshoot.FrameSource(width=800, height=600)
    
    # Handle safe defaults if client connects before an experiment starts
    current_experiment = state.get("experiment_type", "unknown")
    if state.get("steps") and state.get("current_step", 0) < len(state["steps"]):
        current_step_text = state["steps"][state["current_step"]]
    else:
        current_step_text = "Waiting for experiment to start"

    prompt = f"You are a lab assistant. The student is performing a {current_experiment} experiment. Current step: {current_step_text}. Watch the video and in 1-2 sentences: confirm if the action is correct, or flag an error. Be specific and concise \u2014 your response will be read aloud."
    
    latest_guidance = ""
    last_spoken_guidance = ""

    async def handle_result(r):
        nonlocal latest_guidance
        latest_guidance = r.result

    stream = await client.streams.create(
        source=source,
        prompt=prompt,
        model="Qwen/Qwen3-VL-30B-A3B-Instruct",
        on_result=lambda r: asyncio.create_task(handle_result(r)),
        on_error=lambda e: print(f"[overshoot error] {e}"),
        mode="frame",
        interval_seconds=0.5,
        max_output_tokens=50,
    )
    
    try:
        async with aiohttp.ClientSession() as session:
            async with httpx.AsyncClient() as httpx_client:
                while True:
                    frame = await fetch_frame(session)
                    if frame is not None:
                        source.push_frame(frame)
                    
                    text_to_say = latest_guidance
                    # Only send to TTS if text changed and isn't empty (avoids spamming TTS and draining ElevenLabs credits)
                    if text_to_say and text_to_say != last_spoken_guidance:
                        last_spoken_guidance = text_to_say
                        
                        anthropic_client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
                        current_experiment = state.get("experiment_type", "unknown")
                        current_step_text = state["steps"][state["current_step"]] if state.get("steps") else "Waiting for experiment to start"
                        
                        enrich_prompt = f"You are a lab assistant speaking to a student doing a {current_experiment} experiment on step: {current_step_text}.\n\nThe vision system just said: \"{text_to_say}\"\n\nIn ONE sentence only, add a brief helpful scientific explanation of why this step matters or what the student should be seeing. Keep it simple and natural — it will be read aloud. If the vision system flagged an error, just return the error message unchanged without adding explanation."
                        
                        message = anthropic_client.messages.create(
                            model="claude-sonnet-4-6",
                            max_tokens=100,
                            messages=[
                                {
                                    "role": "user",
                                    "content": enrich_prompt
                                }
                            ]
                        )
                        enriched_text = message.content[0].text
                        
                        tts_url = "https://api.elevenlabs.io/v1/text-to-speech/gJx1vCzNCD1EQHT212Ls"
                        headers = {
                            "Accept": "audio/mpeg",
                            "Content-Type": "application/json",
                            "xi-api-key": ELEVENLABS_API_KEY
                        }
                        data = {
                            "text": enriched_text,
                            "model_id": "eleven_flash_v2_5"
                        }
                        
                        response = await httpx_client.post(tts_url, json=data, headers=headers)
                        
                        if response.status_code == 200:
                            audio_bytes = response.content
                            audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
                            
                            await websocket.send_json({
                                "audio_base64": audio_b64,
                                "text": enriched_text
                            })
                        else:
                            print(f"ElevenLabs API Error: {response.text}")

                    await asyncio.sleep(0.5)
                    
    except WebSocketDisconnect:
        print("Client disconnected from /experiment-stream")
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        try:
            await stream.close()
            await client.close()
        except Exception:
            pass