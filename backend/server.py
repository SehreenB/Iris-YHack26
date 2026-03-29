import os
import json
import asyncio
import aiohttp
import cv2
import numpy as np
import overshoot
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from dotenv import load_dotenv

load_dotenv()

ESP32_URL = os.getenv("ESP32_CAPTURE_URL", "http://192.168.137.77/capture")
API_KEY = os.getenv("OVERSHOOT_APIKEY")
WIDTH = 800
HEIGHT = 600
FETCH_DELAY = 0.2

# ── Load experiment steps ──
with open("steps.json") as f:
    EXPERIMENT = json.load(f)
    STEPS = EXPERIMENT["steps"]

# ── Global state ──
state = {
    "current_step": 0,
    "status": "waiting",       # waiting | in_progress | complete | error
    "last_feedback": "",
    "last_instruction": STEPS[0]["instruction"],
    "history": [],
}
state_lock = asyncio.Lock()


def build_prompt(step_id: int) -> str:
    step = STEPS[step_id]
    prev_steps = STEPS[:step_id]

    completed = "\n".join(
        f"  - Step {s['id']}: {s['name']} ✓" for s in prev_steps
    ) if prev_steps else "  None yet."

    return f"""You are a lab assistant guiding a chemistry experiment through a camera feed.
You analyze each frame and return structured JSON — nothing else.

EXPERIMENT: {EXPERIMENT['experiment']}

COMPLETED STEPS:
{completed}

CURRENT STEP (Step {step['id']}): {step['name']}
INSTRUCTION: {step['instruction']}
WHAT TO DETECT: {step['detect']}
POSSIBLE ERRORS (BUT NOT LIMITED TO THIS LIST): {json.dumps(step['errors'])}

RULES:
1. Look at the frame. Determine if the current step's detection criteria is met.
2. If an error is happening (wrong flask, wrong item, spilling), report it immediately.
3. Keep feedback short — 1-2 sentences max, spoken aloud to the user.
4. Do NOT skip steps. Only advance when detection criteria is clearly met.
5. If unsure, stay on the current step and repeat the instruction.

Respond with ONLY this JSON (no markdown, no backticks):
{{"step_complete": true/false, "error": true/false, "feedback": "short spoken feedback to the user"}}"""


def parse_result(text: str) -> dict | None:
    text = text.strip()
    # Strip markdown fences if present
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0]
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Try to find JSON in the text
        start = text.find("{")
        end = text.rfind("}") + 1
        if start >= 0 and end > start:
            try:
                return json.loads(text[start:end])
            except json.JSONDecodeError:
                return None
    return None


async def handle_result(result):
    parsed = parse_result(result.result)
    if not parsed:
        print(f"[unparsed] {result.result}")
        return

    async with state_lock:
        feedback = parsed.get("feedback", "")
        step_complete = parsed.get("step_complete", False)
        error = parsed.get("error", False)

        state["last_feedback"] = feedback

        if error:
            state["status"] = "error"
            print(f"[step {state['current_step']}] ERROR: {feedback}")
        elif step_complete:
            current = state["current_step"]
            state["history"].append({
                "step": current,
                "name": STEPS[current]["name"],
                "feedback": feedback,
            })

            if current + 1 < len(STEPS):
                state["current_step"] = current + 1
                state["status"] = "in_progress"
                state["last_instruction"] = STEPS[current + 1]["instruction"]
                print(f"[step {current} → {current + 1}] {feedback}")
            else:
                state["status"] = "complete"
                print(f"[DONE] {feedback}")
        else:
            state["status"] = "in_progress"
            print(f"[step {state['current_step']}] {feedback}")


async def fetch_frame(session: aiohttp.ClientSession) -> np.ndarray | None:
    try:
        async with session.get(ESP32_URL, timeout=aiohttp.ClientTimeout(total=5)) as resp:
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


# ── Overshoot vision loop ──
overshoot_client = None
overshoot_stream = None
overshoot_source = None


async def vision_loop():
    global overshoot_client, overshoot_stream, overshoot_source

    overshoot_client = overshoot.Overshoot(api_key=API_KEY)
    overshoot_source = overshoot.FrameSource(width=WIDTH, height=HEIGHT)

    overshoot_stream = await overshoot_client.streams.create(
        source=overshoot_source,
        prompt=build_prompt(0),
        model="Qwen/Qwen3.5-35B-A3B",
        on_result=lambda r: asyncio.create_task(handle_result(r)),
        on_error=lambda e: print(f"[overshoot error] {e}"),
        mode="frame",
        interval_seconds=1.0,
        max_output_tokens=150,
    )

    print(f"Stream {overshoot_stream.stream_id} started")
    last_step = 0

    async with aiohttp.ClientSession() as session:
        while state["status"] != "complete":
            frame = await fetch_frame(session)
            if frame is not None:
                overshoot_source.push_frame(frame)

            # Update prompt when step changes
            async with state_lock:
                current = state["current_step"]
            if current != last_step:
                new_prompt = build_prompt(current)
                await overshoot_stream.update_prompt(new_prompt)
                last_step = current
                print(f"[prompt updated for step {current}]")

            await asyncio.sleep(FETCH_DELAY)

    await overshoot_stream.close()
    await overshoot_client.close()
    print("Vision loop ended.")


# ── FastAPI ──
@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(vision_loop())
    yield
    task.cancel()

app = FastAPI(lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.get("/state")
async def get_state():
    async with state_lock:
        return {
            "current_step": state["current_step"],
            "total_steps": len(STEPS),
            "status": state["status"],
            "instruction": state["last_instruction"],
            "feedback": state["last_feedback"],
            "step_name": STEPS[state["current_step"]]["name"],
            "history": state["history"],
        }


@app.post("/reset")
async def reset_state():
    async with state_lock:
        state["current_step"] = 0
        state["status"] = "waiting"
        state["last_feedback"] = ""
        state["last_instruction"] = STEPS[0]["instruction"]
        state["history"] = []
    if overshoot_stream:
        await overshoot_stream.update_prompt(build_prompt(0))
    return {"status": "reset"}


@app.get("/steps")
async def get_steps():
    return STEPS

@app.get("/test")
async def test_connection():
    print("[test] Connection received from iOS app")
    return {"status": "connected", "current_step": state["current_step"]}