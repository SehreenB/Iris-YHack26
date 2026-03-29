from fastapi import FastAPI, WebSocket, WebSocketDisconnect, File, UploadFile, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt
from jose.exceptions import JWTError
from pydantic import BaseModel
from google import genai
from google.genai import types
import asyncio
import base64
import httpx
import json
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

AUTH0_DOMAIN = os.environ.get("AUTH0_DOMAIN", "dev-3s1g3u3fqfzg6fzi.ca.auth0.com")
AUTH0_AUDIENCE = os.environ.get("AUTH0_AUDIENCE", "https://iris-api")
AUTH0_ALGORITHMS = ["RS256"]
AUTH0_JWKS_URL = f"https://{AUTH0_DOMAIN}/.well-known/jwks.json"

app = FastAPI()

from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

ELEVENLABS_API_KEY = os.environ.get('ELEVENLABS_API_KEY')
GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY')
gemini_client = genai.Client(api_key=GEMINI_API_KEY)

ESP32_CAPTURE_URL = os.environ.get("ESP32_CAPTURE_URL", "http://192.168.137.5/capture")
OVERSHOOT_API_KEY = os.environ.get("OVERSHOOT_APIKEY")

FETCH_DELAY = 0.15
ANALYSIS_INTERVAL = 0.3
CONFIRM_THRESHOLD = 2
consecutive_complete = 0
state_lock = asyncio.Lock()

# State machine - tracks the current experiment
state = {
    "current_step": 0,
    "steps": [],
    "experiment_type": "",
    "lab_document": "",
    "struggles": [],
    "status": "waiting",
    "last_feedback": "",
    "last_audio": None,
    "history": [],
    "last_spoken_step": -1,
    "user_id": ""
}

# Request body model
class ExperimentRequest(BaseModel):
    experiment_type: str

class AskQuestionRequest(BaseModel):
    question: str

class StrugglesRequest(BaseModel):
    struggles: list[str]

class SearchRequest(BaseModel):
    query: str

async def elevenlabs_tts(text: str):
    try:
        url = f"https://api.elevenlabs.io/v1/text-to-speech/gJx1vCzNCD1EQHT212Ls"
        headers = {
            "Accept": "audio/mpeg",
            "Content-Type": "application/json",
            "xi-api-key": ELEVENLABS_API_KEY,
        }
        payload = {
            "text": text,
            "model_id": "eleven_flash_v2_5",
        }
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            resp.raise_for_status()
            return base64.b64encode(resp.content).decode("utf-8")
    except Exception as e:
        print(f"[tts] Error: {e}")
        return None

async def generate_audio(text: str):
    audio = await elevenlabs_tts(text)
    async with state_lock:
        state["last_audio"] = audio

def build_step_prompt(step_index: int) -> str:
    if not state["steps"]:
        return "Watch the experiment and describe what you see in one sentence."
    step = state["steps"][step_index] if step_index < len(state["steps"]) else state["steps"][-1]
    prev_names = ", ".join(
        s.get("name", f"step {i}") for i, s in enumerate(state["steps"][:step_index])
    ) if step_index > 0 else "none"
    errors = step.get("errors", [])
    instruction = step.get("instruction", step) if isinstance(step, dict) else step
    name = step.get("name", f"step_{step_index}") if isinstance(step, dict) else f"step_{step_index}"
    detect = step.get("detect", "student completes the action") if isinstance(step, dict) else "student completes the action"
    return f"""Camera feed of a science experiment. Return JSON only.

Done so far: {prev_names}
Step: {name} — {instruction}

SET done=true WHEN: {detect}
SET err=true ONLY WHEN: {", ".join(errors) if errors else "never"}

Return: {{"done": true/false, "err": false, "msg": "one sentence"}}"""

def parse_overshoot_result(text: str) -> dict:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
    start = text.find("{")
    end = text.rfind("}") + 1
    if start >= 0 and end > start:
        try:
            parsed = json.loads(text[start:end])
            if "done" in parsed and "msg" in parsed:
                return parsed
        except:
            pass
    return {"done": False, "err": False, "msg": text[:100]}

security = HTTPBearer()

async def get_jwks():
    async with httpx.AsyncClient() as client:
        response = await client.get(AUTH0_JWKS_URL)
        return response.json()

async def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    try:
        jwks = await get_jwks()
        unverified_header = jwt.get_unverified_header(token)
        rsa_key = {}
        for key in jwks["keys"]:
            if key["kid"] == unverified_header["kid"]:
                rsa_key = {
                    "kty": key["kty"],
                    "kid": key["kid"],
                    "use": key["use"],
                    "n": key["n"],
                    "e": key["e"]
                }
                break
        if not rsa_key:
            raise HTTPException(status_code=401, detail="Invalid token key")
        
        payload = jwt.decode(
            token,
            rsa_key,
            algorithms=AUTH0_ALGORITHMS,
            audience=AUTH0_AUDIENCE,
            issuer=f"https://{AUTH0_DOMAIN}/"
        )
        return payload
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Authentication failed: {str(e)}"
        )

@app.get("/me")
async def get_me(payload: dict = Depends(verify_token)):
    return {
        "user_id": payload.get("sub"),
        "email": payload.get("email"),
        "name": payload.get("name"),
        "authenticated": True
    }

@app.post("/search-experiment")
async def search_experiment(request: SearchRequest, payload: dict = Depends(verify_token)):
    prompt = f"""A student wants to do a "{request.query}" experiment in a science lab.

Return a JSON object with exactly these fields:
{{
  "name": "proper experiment name",
  "subject": "one of: Chemistry, Biology, Physics, Engineering, Medicine, Environmental",
  "difficulty": "one of: Beginner, Intermediate, Advanced",
  "time": "estimated time e.g. 30 min",
  "description": "one sentence description of what the student will learn",
  "steps": ["step 1", "step 2", ...],
  "materials": ["material 1", "material 2", ...]
}}

Steps should be maximum 10 words each. Return ONLY the JSON, nothing else."""

    response = gemini_client.models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt
    )
    
    raw_text = response.text.strip()
    if raw_text.startswith("```json"):
        raw_text = raw_text[7:]
    elif raw_text.startswith("```"):
        raw_text = raw_text[3:]
    if raw_text.endswith("```"):
        raw_text = raw_text[:-3]
    raw_text = raw_text.strip()
    
    try:
        data = json.loads(raw_text)
    except Exception as e:
        return {"error": "Could not parse experiment"}
        
    state["steps"] = data.get("steps", [])
    state["current_step"] = 0
    state["experiment_type"] = data.get("name", "unknown")
    
    return {
        "success": True,
        "name": data.get("name"),
        "subject": data.get("subject"),
        "difficulty": data.get("difficulty"),
        "time": data.get("time"),
        "description": data.get("description"),
        "steps": data.get("steps", []),
        "materials": data.get("materials", [])
    }

@app.post("/set-struggles")
async def set_struggles(request: StrugglesRequest, payload: dict = Depends(verify_token)):
    state["struggles"] = request.struggles
    return {"success": True, "struggles": state["struggles"]}

@app.get("/")
def root():
    return {"message": "Iris backend is running"}

@app.post("/start-experiment")
async def start_experiment(request: ExperimentRequest, payload: dict = Depends(verify_token)):
    state["user_id"] = payload.get("sub", "anonymous")
    
    struct_prompt = f"""Generate steps for a {request.experiment_type} experiment in a science lab.
Return a JSON array only. Each step must have exactly these fields:
{{
  "id": 0,
  "name": "short_snake_case_name",
  "instruction": "What the student should do, maximum 10 words",
  "detect": "what the camera should see to confirm this step is complete",
  "errors": ["what would indicate a mistake, or empty array if none"]
}}
Return ONLY the JSON array, nothing else. Maximum 10 steps."""

    response = gemini_client.models.generate_content(
        model='gemini-2.5-flash',
        contents=struct_prompt
    )
    raw_text = response.text.strip()
    if raw_text.startswith("```"):
        raw_text = raw_text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
        if raw_text.startswith("json"):
            raw_text = raw_text[4:].strip()
    try:
        steps = json.loads(raw_text)
    except:
        steps = []
    
    materials_prompt = f"List the materials and equipment needed for a {request.experiment_type} experiment in a science lab. Return ONLY a JSON array of strings, nothing else. Example: [\"beaker\", \"burette\", \"indicator\"]. Maximum 10 items."

    materials_response = gemini_client.models.generate_content(
        model='gemini-2.5-flash',
        contents=materials_prompt
    )

    import json as json_module
    materials_text = materials_response.text.strip()
    if materials_text.startswith("```"):
        materials_text = materials_text.split("```")[1]
        if materials_text.startswith("json"):
            materials_text = materials_text[4:]
    materials_text = materials_text.strip()
    try:
        materials = json_module.loads(materials_text)
    except:
        materials = []
    
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
        "materials": materials,
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
async def ask_question(request: AskQuestionRequest, payload: dict = Depends(verify_token)):
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
async def end_experiment(payload: dict = Depends(verify_token)):
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
async def generate_report(payload: dict = Depends(verify_token)):
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

@app.get("/state")
async def get_state():
    async with state_lock:
        response = {
            "current_step": state["current_step"],
            "total_steps": len(state["steps"]),
            "status": state["status"],
            "instruction": state["steps"][state["current_step"]].get("instruction", "") if state["steps"] and isinstance(state["steps"][state["current_step"]], dict) else (state["steps"][state["current_step"]] if state["steps"] else ""),
            "feedback": state["last_feedback"],
            "history": state["history"],
            "audio_base64": state["last_audio"],
        }
        state["last_audio"] = None
        return response

@app.post("/reset")
async def reset_state():
    global consecutive_complete
    async with state_lock:
        state["current_step"] = 0
        state["last_spoken_step"] = -1
        state["status"] = "waiting"
        state["last_feedback"] = ""
        state["history"] = []
        consecutive_complete = 0
    return {"status": "reset"}

@app.websocket("/experiment-stream")
async def experiment_stream(websocket: WebSocket):
    global consecutive_complete
    await websocket.accept()

    overshoot_client = overshoot.Overshoot(api_key=OVERSHOOT_API_KEY)
    source = overshoot.FrameSource(width=800, height=600)

    latest_result = {"done": False, "err": False, "msg": ""}
    last_spoken_guidance = ""

    async def handle_result(r):
        nonlocal latest_result
        parsed = parse_overshoot_result(r.result)
        latest_result = parsed

    prompt = build_step_prompt(state.get("current_step", 0))

    stream = await overshoot_client.streams.create(
        source=source,
        prompt=prompt,
        model="Qwen/Qwen3-VL-30B-A3B-Instruct",
        on_result=lambda r: asyncio.create_task(handle_result(r)),
        on_error=lambda e: print(f"[overshoot error] {e}"),
        mode="frame",
        interval_seconds=0.5,
        max_output_tokens=76,
    )

    try:
        async with aiohttp.ClientSession() as session:
            async with httpx.AsyncClient() as httpx_client:
                last_step = state.get("current_step", 0)
                while True:
                    frame = await fetch_frame(session)
                    if frame is not None:
                        source.push_frame(frame)

                    result = latest_result
                    current_step = state.get("current_step", 0)

                    # Update prompt if step changed
                    if current_step != last_step:
                        new_prompt = build_step_prompt(current_step)
                        await stream.update_prompt(new_prompt)
                        last_step = current_step

                    # Auto-advance if step complete
                    if result.get("done") and not result.get("err"):
                        consecutive_complete += 1
                        if consecutive_complete >= CONFIRM_THRESHOLD:
                            if current_step < len(state["steps"]) - 1:
                                state["current_step"] += 1
                                state["status"] = "in_progress"
                                consecutive_complete = 0
                                print(f"[auto-advance] Step {state['current_step']}")
                            else:
                                state["status"] = "complete"
                                consecutive_complete = 0
                    elif result.get("err"):
                        consecutive_complete = 0
                        state["status"] = "error"

                    # Send audio if guidance changed
                    msg = result.get("msg", "")
                    if msg and msg != last_spoken_guidance:
                        last_spoken_guidance = msg

                        struggles_text = ", ".join(state["struggles"]) if state.get("struggles") else "none specified"
                        current_step_data = state["steps"][current_step] if state.get("steps") and current_step < len(state["steps"]) else {}
                        step_instruction = current_step_data.get("instruction", "") if isinstance(current_step_data, dict) else str(current_step_data)

                        enrich_prompt = f"You are a lab assistant speaking to a student doing a {state.get('experiment_type', 'science')} experiment on step: {step_instruction}. The student struggles with: {struggles_text}. The vision system just said: \"{msg}\" In ONE sentence only, add a brief helpful tip or scientific explanation. Keep it simple and natural — it will be read aloud. If the vision system flagged an error, return the error message unchanged."

                        response = gemini_client.models.generate_content(
                            model='gemini-2.5-flash',
                            contents=enrich_prompt
                        )
                        enriched_text = response.text

                        audio_b64 = await elevenlabs_tts(enriched_text)
                        if audio_b64:
                            await websocket.send_json({
                                "audio_base64": audio_b64,
                                "text": enriched_text,
                                "step": current_step,
                                "status": state.get("status", "in_progress")
                            })

                    await asyncio.sleep(0.5)

    except WebSocketDisconnect:
        print("Client disconnected from /experiment-stream")
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        try:
            await stream.close()
            await overshoot_client.close()
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