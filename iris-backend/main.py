from fastapi import FastAPI, WebSocket, WebSocketDisconnect, File, UploadFile
from pydantic import BaseModel
from google import genai
from google.genai import types
import asyncio
import base64
import httpx
import os
from dotenv import load_dotenv

import PyPDF2
import docx
from io import BytesIO

import aiohttp
import cv2
import numpy as np
import overshoot

load_dotenv()

app = FastAPI()

ELEVENLABS_API_KEY = os.environ.get('ELEVENLABS_API_KEY')
GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY')
gemini_client = genai.Client(api_key=GEMINI_API_KEY)

ESP32_CAPTURE_URL = os.environ.get("ESP32_CAPTURE_URL", "http://192.168.137.5/capture")
OVERSHOOT_API_KEY = os.environ.get("OVERSHOOT_APIKEY")

# State machine - tracks the current experiment
state = {
    "current_step": 0,
    "steps": [],
    "experiment_type": "",
    "lab_document": "",
    "struggles": []
}

# Request body model
class ExperimentRequest(BaseModel):
    experiment_type: str

class AskQuestionRequest(BaseModel):
    question: str

class StrugglesRequest(BaseModel):
    struggles: list[str]

@app.post("/set-struggles")
async def set_struggles(request: StrugglesRequest):
    state["struggles"] = request.struggles
    return {"success": True, "struggles": state["struggles"]}

@app.get("/")
def root():
    return {"message": "Iris backend is running"}

@app.post("/start-experiment")
async def start_experiment(request: ExperimentRequest):
    
    response = gemini_client.models.generate_content(
        model='gemini-2.5-flash',
        contents=f"List the step-by-step instructions for a {request.experiment_type} experiment in a science lab. Return ONLY a numbered list of steps, nothing else. Keep each step short and clear, maximum 10 words per step."
    )
    raw_text = response.text
    lines = raw_text.strip().split("\n")
    steps = [line.strip() for line in lines if line.strip()]
    
    state["steps"] = steps
    state["current_step"] = 0
    state["experiment_type"] = request.experiment_type
    
    first_step_text = steps[0] if steps else ""
    tts_url = "https://api.elevenlabs.io/v1/text-to-speech/gJx1vCzNCD1EQHT212Ls"
    headers = {
        "Accept": "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": ELEVENLABS_API_KEY
    }
    data = {
        "text": f"Experiment started. Step one: {first_step_text}",
        "model_id": "eleven_flash_v2_5"
    }
    
    audio_b64 = ""
    async with httpx.AsyncClient() as httpx_client:
        response = await httpx_client.post(tts_url, json=data, headers=headers)
        if response.status_code == 200:
            audio_b64 = base64.b64encode(response.content).decode('utf-8')
    
    return {
        "success": True,
        "experiment_type": request.experiment_type,
        "steps": steps,
        "current_step": 0,
        "audio_base64": audio_b64
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
async def advance_step():
    if not state["steps"]:
        return {"error": "No experiment started"}
    
    if state["current_step"] < len(state["steps"]) - 1:
        state["current_step"] += 1
        instruction = state["steps"][state["current_step"]]
        
        tts_url = "https://api.elevenlabs.io/v1/text-to-speech/gJx1vCzNCD1EQHT212Ls"
        headers = {
            "Accept": "audio/mpeg",
            "Content-Type": "application/json",
            "xi-api-key": ELEVENLABS_API_KEY
        }
        data = {
            "text": f"Next step: {instruction}",
            "model_id": "eleven_flash_v2_5"
        }
        
        audio_b64 = ""
        async with httpx.AsyncClient() as httpx_client:
            response = await httpx_client.post(tts_url, json=data, headers=headers)
            if response.status_code == 200:
                audio_b64 = base64.b64encode(response.content).decode('utf-8')

        return {
            "success": True,
            "current_step": state["current_step"],
            "instruction": instruction,
            "audio_base64": audio_b64
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
        
    prompt = f"You are a lab assistant helping a student with a {state['experiment_type']} experiment. They are currently on this step: {state['steps'][state['current_step']]}. The student asks: {request.question}. Answer in 2-3 sentences maximum. Be clear, helpful and simple \u2014 your response will be read aloud to the student."
    
    response = gemini_client.models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt
    )
    answer_text = response.text
    
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

    response = gemini_client.models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt
    )
    summary_text = response.text
    
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
        state["lab_document"] = ""
        state["struggles"] = []
        
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

@app.post("/upload-document")
async def upload_document(file: UploadFile = File(...)):
    contents = await file.read()
    filename = file.filename.lower()
    
    extracted_text = ""
    
    if filename.endswith(".pdf"):
        pdf_reader = PyPDF2.PdfReader(BytesIO(contents))
        for page in pdf_reader.pages:
            extracted_text += page.extract_text() + "\n"
    elif filename.endswith(".docx"):
        doc = docx.Document(BytesIO(contents))
        for para in doc.paragraphs:
            extracted_text += para.text + "\n"
    elif filename.endswith(".txt"):
        extracted_text = contents.decode("utf-8")
    else:
        return {"error": "Unsupported file format. Please upload PDF, DOCX, or TXT."}
        
    state["lab_document"] = extracted_text
    
    prompt = f"You are a lab assistant. Here is a lab document a student uploaded:\n\n{extracted_text}\n\nExtract and return ONLY a numbered list of the procedure steps the student needs to follow. Maximum 10 words per step. Return nothing else."
    
    response = gemini_client.models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt
    )
    raw_text = response.text
    lines = raw_text.strip().split("\n")
    steps = [line.strip() for line in lines if line.strip()]
    
    state["steps"] = steps
    state["current_step"] = 0
    state["experiment_type"] = "document-based" # Fallback if not set
    
    return {
        "success": True,
        "steps_extracted": len(steps),
        "steps": steps
    }

@app.post("/generate-report")
async def generate_report():
    if not state.get("steps"):
        return {"error": "No experiment completed"}
    
    struggles_text = ", ".join(state["struggles"]) if state.get("struggles") else "general guidance"
    lab_doc_context = f"\nOriginal lab document they were given:\n{state['lab_document']}" if state.get("lab_document") else ""
    
    prompt = f"""You are an experienced science teacher and TA helping a student write their own lab report for a {state["experiment_type"]} experiment.

The student struggles with: {struggles_text}
Steps they completed: {state["steps"][:state["current_step"]+1]}
{lab_doc_context}

Do NOT write the lab report for them. Instead do the following:

1. REQUIRED SECTIONS: Based on the lab document above, identify exactly which sections their lab report needs. If no document was uploaded, use standard sections: Title, Objective, Materials, Procedure, Observations, Conclusion.

2. FOR EACH SECTION: Give them 2-3 specific guiding questions to answer based on what they actually did in the experiment. If the section relates to their struggle areas, give extra detailed step-by-step tips.

3. GRADING TIPS: After each section, add a "What TAs and professors love to see" tip \u2014 specific things that get bonus marks like significant figures, proper units, error analysis, passive voice in procedure, linking observations to theory in conclusions.

4. STRUGGLE COACHING: For sections that match their struggle areas ({struggles_text}), add a dedicated "Extra help for you" block with very specific advice tailored to that struggle. For example if they struggle with measurement, remind them to include units, significant figures, and uncertainty values. If they struggle with procedure writing, remind them about passive voice, past tense, and reproducibility.

5. End with one encouraging sentence and a checklist of everything they need to submit.

Keep it warm, specific, and actionable. The student will read this and use it to write their report themselves."""

    response = gemini_client.models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt
    )
    
    coaching_text = response.text
    
    return {
        "coaching_text": coaching_text,
        "struggles_addressed": state.get("struggles", []),
        "sections_to_complete": ["Title", "Objective", "Materials", "Procedure", "Observations", "Conclusion"]
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
                        
                        current_experiment = state.get("experiment_type", "unknown")
                        current_step_text = state["steps"][state["current_step"]] if state.get("steps") else "Waiting for experiment to start"
                        
                        struggles_text = ", ".join(state["struggles"]) if state.get("struggles") else "none specified"
                        enrich_prompt = f"You are a lab assistant speaking to a student doing a {current_experiment} experiment on step: {current_step_text}. The student has told you they struggle with: {struggles_text}. The vision system just said: \"{text_to_say}\" In ONE sentence only, add a brief helpful tip tailored to their struggles if relevant, or a scientific explanation of what they should be seeing. Keep it simple and natural \u2014 it will be read aloud. If the vision system flagged an error, just return the error message unchanged without adding explanation."
                        
                        response = gemini_client.models.generate_content(
                            model='gemini-2.5-flash',
                            contents=enrich_prompt
                        )
                        enriched_text = response.text
                        
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

@app.websocket("/phone-stream")
async def phone_stream(websocket: WebSocket):
    await websocket.accept()
    
    client = overshoot.Overshoot(api_key=OVERSHOOT_API_KEY)
    source = overshoot.FrameSource(width=800, height=600)
    
    stream = None
    latest_guidance = ""
    last_spoken_guidance = ""
    
    async def handle_result(r):
        nonlocal latest_guidance
        latest_guidance = r.result
        
    try:
        async with httpx.AsyncClient() as httpx_client:
            while True:
                data = await websocket.receive_json()
                
                frame_b64 = data.get("frame")
                exp_type = data.get("experiment_type", "unknown")
                current_step_text = data.get("current_step", "unknown")
                
                if not stream:
                    # Initialize overshoot stream on first frame
                    prompt = f"You are a lab assistant. The student is performing a {exp_type} experiment. Current step: {current_step_text}. Watch the video and in 1-2 sentences: confirm if the action is correct, or flag an error. Be specific and concise \u2014 your response will be read aloud."
                    
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
                
                if frame_b64:
                    frame_bytes = base64.b64decode(frame_b64)
                    bgr = cv2.imdecode(np.frombuffer(frame_bytes, np.uint8), cv2.IMREAD_COLOR)
                    if bgr is not None:
                        bgr = cv2.resize(bgr, (800, 600), interpolation=cv2.INTER_LINEAR)
                        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
                        rgba = cv2.cvtColor(rgb, cv2.COLOR_RGB2RGBA)
                        source.push_frame(np.ascontiguousarray(rgba))
                        
                text_to_say = latest_guidance
                if text_to_say and text_to_say != last_spoken_guidance:
                    last_spoken_guidance = text_to_say
                    
                    struggles_text = ", ".join(state["struggles"]) if state.get("struggles") else "none specified"
                    
                    enrich_prompt = f"You are a lab assistant speaking to a student doing a {exp_type} experiment on step: {current_step_text}. The student has told you they struggle with: {struggles_text}. The vision system just said: \"{text_to_say}\" In ONE sentence only, add a brief helpful tip tailored to their struggles if relevant, or a scientific explanation of what they should be seeing. Keep it simple and natural \u2014 it will be read aloud. If the vision system flagged an error, just return the error message unchanged without adding explanation."
                    
                    response = gemini_client.models.generate_content(
                        model='gemini-2.5-flash',
                        contents=enrich_prompt
                    )
                    enriched_text = response.text
                    
                    tts_url = "https://api.elevenlabs.io/v1/text-to-speech/gJx1vCzNCD1EQHT212Ls"
                    headers = {
                        "Accept": "audio/mpeg",
                        "Content-Type": "application/json",
                        "xi-api-key": ELEVENLABS_API_KEY
                    }
                    tts_data = {
                        "text": enriched_text,
                        "model_id": "eleven_flash_v2_5"
                    }
                    
                    response = await httpx_client.post(tts_url, json=tts_data, headers=headers)
                    if response.status_code == 200:
                        audio_b64 = base64.b64encode(response.content).decode('utf-8')
                        
                        await websocket.send_json({
                            "audio_base64": audio_b64,
                            "text": enriched_text
                        })
                    else:
                        print(f"ElevenLabs API Error: {response.text}")
                        
    except WebSocketDisconnect:
        print("Client disconnected from /phone-stream")
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        try:
            if stream:
                await stream.close()
            await client.close()
        except Exception:
            pass