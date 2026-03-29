"""Iris — ESP32 camera → Overshoot → FastAPI state server"""

import os
import json
import asyncio
import base64
import aiohttp
import cv2
import numpy as np
import overshoot
import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from pydantic import BaseModel
from google import genai

load_dotenv()

ESP32_URL = os.getenv("ESP32_CAPTURE_URL", "http://192.168.137.77/capture")
API_KEY = os.getenv("OVERSHOOT_APIKEY")
ELEVENLABS_API_KEY = os.getenv("ELEVENLABS_API_KEY", "").strip()
ELEVENLABS_VOICE_ID = os.getenv("ELEVENLABS_VOICE_ID", "").strip()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
gemini_client = genai.Client(api_key=GEMINI_API_KEY)
WIDTH = 800
HEIGHT = 600
FETCH_DELAY = 0.15
ANALYSIS_INTERVAL = 0.3
CONFIRM_THRESHOLD = 1

with open("steps.json") as f:
    EXPERIMENT = json.load(f)
    STEPS = EXPERIMENT["steps"]

state = {
    "current_step": 0,
    "status": "waiting",
    "last_feedback": "",
    "last_instruction": STEPS[0]["instruction"],
    "last_audio": None,
    "history": [],
    "last_spoken_step": -1,
}
state_lock = asyncio.Lock()
consecutive_complete = 0


# ── TTS ──

async def elevenlabs_tts(text: str) -> str | None:
    if not ELEVENLABS_API_KEY or not ELEVENLABS_VOICE_ID:
        print("[tts] Missing API key or voice ID")
        return None
    try:
        # Correct ElevenLabs URL and Headers
        url = f"https://api.elevenlabs.io/v1/text-to-speech/{ELEVENLABS_VOICE_ID}"
        headers = {
            "Accept": "audio/mpeg",
            "Content-Type": "application/json",
            "xi-api-key": ELEVENLABS_API_KEY,
        }
        payload = {
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": {
                "stability": 0.45,
                "similarity_boost": 0.8,
            },
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


# ── Prompt ──

def build_prompt(step_id: int) -> str:
    step = STEPS[step_id]
    prev_names = ", ".join(s["name"] for s in STEPS[:step_id]) if step_id > 0 else "none"

    return f"""Camera feed of a chemistry experiment. Return JSON only.

Done so far: {prev_names}
Step: {step['name']} — {step['instruction']}

SET done=true WHEN: {step['detect']}
SET err=true ONLY WHEN: {', '.join(step['errors']) if step['errors'] else 'never'}

If what you see matches the done=true condition, you MUST return done=true. Example:
Condition: "yellow box is near the green flask" → You see: "hand holds yellow box above green flask" → MATCH → done=true

Return: {{"done": true/false, "err": false, "msg": "one sentence"}}"""


# ── Parse ──

def parse_result(text: str) -> dict | None:
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
        except json.JSONDecodeError:
            pass

    result = {"done": False, "err": False, "msg": ""}
    raw = text.replace("\n", " ")

    if "done=true" in raw or "done: true" in raw or '"done": true' in raw or "done:true" in raw:
        result["done"] = True

    if "err=true" in raw or "err: true" in raw or '"err": true' in raw or "err:true" in raw:
        result["err"] = True

    msg = ""
    for pattern in ["msg:", "msg=", '"msg":', '"msg"=']:
        idx = raw.lower().find(pattern.lower())
        if idx >= 0:
            msg = raw[idx + len(pattern):].strip().strip('"').strip("'")
            for stop in [" done", " err", "}", "\n"]:
                stop_idx = msg.find(stop)
                if stop_idx > 0:
                    msg = msg[:stop_idx]
            break

    if not msg:
        clean = raw.strip().strip('"')
        if len(clean) < 200 and "done" not in clean.lower()[:10]:
            msg = clean

    result["msg"] = msg.strip().strip('"').strip("'")

    if result["msg"] and len(result["msg"]) >= 3:
        return result

    return None


# ── Handle Overshoot result ──

SILENT_KEYWORDS = {"no flask", "nothing detected", "waiting", "searching", "no action"}

# ── Handle Overshoot result ──

async def handle_result(result):
    global consecutive_complete
    raw = result.result
    if not raw or not raw.strip():
        return

    parsed = parse_result(raw)
    if not parsed:
        return

    msg = parsed.get("msg", "").strip()
    step_done = parsed.get("done", False)
    error = parsed.get("err", False)

    async with state_lock:
        # ── NEW: FIRST APPEARANCE TRIGGER ──
        # If we just entered this step, announce it immediately
        if state["current_step"] > state["last_spoken_step"]:
            current_instr = STEPS[state["current_step"]]["instruction"]
            state["last_spoken_step"] = state["current_step"]
            
            # Use a slightly different intro for the very first step
            prefix = "Starting experiment. " if state["current_step"] == 0 else "Step complete. "
            asyncio.create_task(generate_audio(f"{prefix}Step {state['current_step'] + 1}: {current_instr}"))
            
            # Optional: Clear the UI feedback when a new step starts
            state["last_feedback"] = ""

        # ── EXISTING SUBTLE LOGIC ──
        if error and not step_done:
            if state["status"] != "error":
                state["status"] = "error"
                state["last_feedback"] = f"Correction: {msg}"
                asyncio.create_task(generate_audio(f"Wait. {msg}"))
            consecutive_complete = 0

        elif step_done and not error:
            consecutive_complete += 1
            if consecutive_complete >= CONFIRM_THRESHOLD:
                current = state["current_step"]
                state["history"].append({
                    "step": current,
                    "name": STEPS[current]["name"],
                    "feedback": msg,
                })
                
                if current + 1 < len(STEPS):
                    # We just increment the index. 
                    # The "First Appearance" block above will handle the speaking on the next frame.
                    state["current_step"] = current + 1
                    state["status"] = "in_progress"
                else:
                    state["status"] = "complete"
                    state["last_feedback"] = "Experiment finished!"
                    asyncio.create_task(generate_audio("All steps finished. Great job!"))
                
                consecutive_complete = 0
        else:
            # Subtle: Print to console, but don't touch state["last_feedback"] or trigger audio
            print(f"[step {state['current_step']}] Watching: {msg}")

# ── Frame fetch ──

async def fetch_frame(session: aiohttp.ClientSession) -> np.ndarray | None:
    try:
        async with session.get(ESP32_URL, timeout=aiohttp.ClientTimeout(total=3)) as resp:
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

    h, w = bgr.shape[:2]
    if w != WIDTH or h != HEIGHT:
        bgr = cv2.resize(bgr, (WIDTH, HEIGHT), interpolation=cv2.INTER_LINEAR)

    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    rgba = cv2.cvtColor(rgb, cv2.COLOR_RGB2RGBA)
    return np.ascontiguousarray(rgba)


# ── Vision loop ──

overshoot_client = None
overshoot_stream = None
overshoot_source = None


async def vision_loop():
    global overshoot_client, overshoot_stream, overshoot_source

    # VOICE TRIGGER: Speak the first instruction once when the loop starts
    async with state_lock:
        first_instruction = STEPS[0]["instruction"]
        asyncio.create_task(generate_audio(f"Starting experiment. Step 1: {first_instruction}"))

    while state["status"] != "complete":
        try:
            print("[vision] Starting Overshoot client...")
            overshoot_client = overshoot.Overshoot(api_key=API_KEY)
            overshoot_source = overshoot.FrameSource(width=WIDTH, height=HEIGHT)

            async with state_lock:
                current = state["current_step"]

            print("[vision] Creating stream...")
            overshoot_stream = await overshoot_client.streams.create(
                source=overshoot_source,
                prompt=build_prompt(current),
                model="Qwen/Qwen3-VL-8B-Instruct",
                on_result=lambda r: asyncio.create_task(handle_result(r)),
                on_error=lambda e: print(f"[overshoot error] {e}"),
                mode="frame",
                interval_seconds=ANALYSIS_INTERVAL,
                max_output_tokens=76,
            )

            print(f"[vision] Stream {overshoot_stream.stream_id} started")
            last_step = current

            async with aiohttp.ClientSession() as session:
                while state["status"] != "complete":
                    frame = await fetch_frame(session)
                    if frame is not None:
                        overshoot_source.push_frame(frame)

                    async with state_lock:
                        current = state["current_step"]
                    if current != last_step:
                        new_prompt = build_prompt(current)
                        await overshoot_stream.update_prompt(new_prompt)
                        last_step = current
                        print(f"[prompt updated for step {current}]")

                    await asyncio.sleep(FETCH_DELAY)

        except Exception as e:
            print(f"[vision] CRASHED: {type(e).__name__}: {e}")
            print("[vision] Reconnecting in 3 seconds...")
            try:
                if overshoot_stream:
                    await overshoot_stream.close()
                if overshoot_client:
                    await overshoot_client.close()
            except Exception:
                pass
            await asyncio.sleep(3)

    try:
        if overshoot_stream:
            await overshoot_stream.close()
        if overshoot_client:
            await overshoot_client.close()
    except Exception:
        pass
    print("[vision] Loop ended.")


# ── FastAPI ──

@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(vision_loop())
    yield
    task.cancel()

app = FastAPI(lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.get("/test")
async def test_connection():
    print("[test] iOS app connected")
    return {"status": "connected", "current_step": state["current_step"]}


@app.get("/state")
async def get_state():
    async with state_lock:
        response = {
            "current_step": state["current_step"],
            "total_steps": len(STEPS),
            "status": state["status"],
            "instruction": state["last_instruction"],
            "feedback": state["last_feedback"],
            "step_name": STEPS[state["current_step"]]["name"],
            "history": state["history"],
            "audio_base64": state["last_audio"],
        }
        state["last_audio"] = None
        return response


# ── Helper for Instant Speech ──

async def announce_step_if_new():
    async with state_lock:
        if state["current_step"] > state["last_spoken_step"]:
            state["last_spoken_step"] = state["current_step"]
            current_instr = STEPS[state["current_step"]]["instruction"]
            
            # Decide on the prefix based on step number
            if state["current_step"] == 0:
                text = f"Starting experiment. Step 1: {current_instr}"
            else:
                text = f"Step complete. Next: {current_instr}"
            
            asyncio.create_task(generate_audio(text))
            # Clear old vision feedback for the new step
            state["last_feedback"] = ""

# ── Manual Advance Endpoint ──

@app.post("/advance")
async def advance_step():
    async with state_lock:
        if state["current_step"] < len(STEPS) - 1:
            state["current_step"] += 1
            state["status"] = "in_progress"
            print(f"[MANUAL ADVANCE] Moved to step {state['current_step']}")
        else:
            print("[MANUAL ADVANCE] Already at final step")
    
    # Trigger voice immediately
    await announce_step_if_new()
    return {"status": "advanced", "current_step": state["current_step"]}

# ── Update Reset Endpoint ──

@app.post("/reset")
async def reset_state():
    global consecutive_complete
    async with state_lock:
        state["current_step"] = 0
        state["last_spoken_step"] = -1 # Critical: Reset the voice tracker
        state["status"] = "waiting"
        state["last_feedback"] = ""
        state["history"] = []
        consecutive_complete = 0
    
    if overshoot_stream:
        await overshoot_stream.update_prompt(build_prompt(0))
    
    # VOICE TRIGGER: Instant announcement of Step 1
    await announce_step_if_new()
    return {"status": "reset"}


@app.get("/steps")
async def get_steps():
    return STEPS

# ── Gemini Q&A ──

async def gemini_answer(question: str, step_id: int) -> str | None:
    if not GEMINI_API_KEY:
        print("[gemini] Missing API key")
        return None

    step = STEPS[step_id] if step_id < len(STEPS) else STEPS[-1]
    completed = [STEPS[i]["name"] for i in range(step_id)]

    prompt = f"""You are IRIS, a concise real-time lab assistant guiding a student through an experiment.

Experiment: {EXPERIMENT['experiment']}
Completed steps: {', '.join(completed) if completed else 'none'}
Current step: {step['name']} — {step['instruction']}
All steps: {json.dumps([s['instruction'] for s in STEPS])}

Student asks: "{question}"

Rules:
- Answer in 1-2 short spoken sentences. You will be read aloud.
- Stay focused on the current step and experiment.
- If they ask what to do next, tell them the current step instruction.
- Be helpful, direct, and encouraging.
- Do not use markdown, bullet points, or formatting."""

    try:
        # This call uses the 2026 stable Gemini 2.5 Flash model
        response = gemini_client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt
        )
        return response.text.strip()
    except Exception as e:
        print(f"[gemini] Error: {e}")
        return None


class AskRequest(BaseModel):
    question: str

@app.post("/ask")
async def ask_endpoint(req: AskRequest):
    async with state_lock:
        current = state["current_step"]

    print(f"[ask] Q: {req.question}")

    # Get Gemini answer
    answer = await gemini_answer(req.question, current)
    if not answer:
        answer = f"Focus on the current step: {STEPS[current]['instruction']}"

    print(f"[ask] A: {answer}")

    # Generate TTS
    audio = await elevenlabs_tts(answer)

    return {
        "status": "ok",
        "answer": answer,
        "audio_base64": audio,
    }


class TTSRequest(BaseModel):
    text: str

@app.post("/tts")
async def tts_endpoint(req: TTSRequest):
    audio = await elevenlabs_tts(req.text)
    if not audio:
        return {"status": "error", "audio_base64": None}
    return {"status": "ok", "audio_base64": audio}