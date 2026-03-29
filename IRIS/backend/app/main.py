from __future__ import annotations

import base64
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Literal
from uuid import uuid4

import httpx
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field


ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "").strip()
ELEVENLABS_API_KEY = os.getenv("ELEVENLABS_API_KEY", "").strip()
ELEVENLABS_VOICE_ID = os.getenv("ELEVENLABS_VOICE_ID", "").strip()
ANTHROPIC_MODEL = os.getenv("ANTHROPIC_MODEL", "claude-3-5-sonnet-latest").strip()

app = FastAPI(title="IRIS Backend", version="0.2.0")


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Procedure(BaseModel):
    id: str
    name: str
    subject: str
    difficulty: str
    time: str
    description: str
    steps: list[str]
    materials: list[str]


class StartSessionRequest(BaseModel):
    experiment_name: str = Field(alias="experimentName")
    subject: str
    difficulty: str | None = None
    time: str | None = None
    description: str | None = None
    steps: list[str]
    materials: list[str] = []
    camera_source: str | None = Field(default=None, alias="cameraSource")

    model_config = {"populate_by_name": True}


class SessionStartedResponse(BaseModel):
    session_id: str = Field(alias="sessionId")
    status: str
    guidance: str


class QuestionRequest(BaseModel):
    experiment_name: str = Field(alias="experimentName")
    subject: str
    current_step_index: int = Field(alias="currentStepIndex")
    current_step: str = Field(alias="currentStep")
    question: str
    materials: list[str] = []
    session_id: str | None = Field(default=None, alias="sessionId")

    model_config = {"populate_by_name": True}


class QuestionResponse(BaseModel):
    answer: str
    status: str
    session_id: str | None = Field(default=None, alias="sessionId")
    audio_base64: str | None = Field(default=None, alias="audioBase64")
    audio_mime_type: str | None = Field(default=None, alias="audioMimeType")

    model_config = {"populate_by_name": True}


class SessionEventRequest(BaseModel):
    type: Literal["question", "confirmed", "warning", "report"]
    message: str


class CompleteSessionRequest(BaseModel):
    procedure: list[str]
    observations: str
    errors: list[str]
    findings: list[str]
    suggestions: list[str]


class CompleteSessionResponse(BaseModel):
    status: str
    report: CompleteSessionRequest
    summary: str


class TTSRequest(BaseModel):
    text: str


class TTSResponse(BaseModel):
    status: str
    audio_base64: str | None = Field(default=None, alias="audioBase64")
    audio_mime_type: str | None = Field(default=None, alias="audioMimeType")

    model_config = {"populate_by_name": True}


@dataclass
class SessionState:
    id: str
    experiment_name: str
    subject: str
    steps: list[str]
    materials: list[str]
    camera_source: str | None = None
    events: list[dict] = field(default_factory=list)
    report: CompleteSessionRequest | None = None
    created_at: datetime = field(default_factory=utc_now)


CATALOG: list[Procedure] = [
    Procedure(
        id="acid-base-titration",
        name="Acid-base titration",
        subject="Chemistry",
        difficulty="Beginner",
        time="20 min",
        description="Determine the concentration of an unknown acid using a standard base solution.",
        steps=[
            "Pour liquid from flask A into the beaker",
            "Add exactly 3 drops of indicator solution",
            "Slowly add liquid from flask B until colour change",
        ],
        materials=["Flask A", "Flask B", "Beaker", "Indicator solution", "Dropper"],
    ),
    Procedure(
        id="dna-extraction",
        name="DNA Extraction",
        subject="Biology",
        difficulty="Intermediate",
        time="45 min",
        description="Extract genomic DNA from strawberry tissue using household chemicals.",
        steps=[
            "Macerate strawberries in a plastic bag",
            "Add extraction buffer and mix gently",
            "Filter the mixture into a test tube",
            "Layer cold ethanol on top to precipitate DNA",
        ],
        materials=["Strawberries", "Dish soap", "Salt", "Ethanol", "Test tube", "Filter"],
    ),
    Procedure(
        id="circuit-analysis",
        name="Circuit Analysis",
        subject="Physics",
        difficulty="Advanced",
        time="60 min",
        description="Measure voltage drops and current in a complex series-parallel circuit.",
        steps=[
            "Assemble the circuit as shown in the diagram",
            "Calibrate the digital multimeter",
            "Measure voltage across each resistor",
            "Calculate total power dissipation",
        ],
        materials=["Resistors", "Breadboard", "Power supply", "Multimeter", "Jumper wires"],
    ),
]

SESSIONS: dict[str, SessionState] = {}


def current_step_text(steps: list[str], step_index: int) -> str:
    if not steps:
        return "Review the imported procedure."
    safe_index = min(max(step_index - 1, 0), len(steps) - 1)
    return steps[safe_index]


def local_answer(question: str, experiment_name: str, step: str, materials: list[str]) -> str:
    lowered = question.lower()
    material_summary = ", ".join(materials[:3]) if materials else "the listed materials"

    if "why" in lowered:
        return f"This step matters because it sets up the experiment correctly before you move on. Focus on: {step}."
    if "what" in lowered and "use" in lowered:
        return f"For this part of {experiment_name}, start with {material_summary} and follow the current step exactly."
    if "next" in lowered or "now" in lowered:
        return f"Your current action is: {step}. Finish that before advancing."
    if "error" in lowered or "wrong" in lowered:
        return f"Pause and compare your setup against the current step: {step}. Double-check positioning and material choice."

    return f"For {experiment_name}, stay on this step: {step}. Use {material_summary} and proceed carefully."


def report_summary(report: CompleteSessionRequest) -> str:
    if report.findings:
        return report.findings[0]
    if report.observations:
        return report.observations
    return "Report completed."


def build_question_prompt(payload: QuestionRequest) -> str:
    materials = ", ".join(payload.materials) if payload.materials else "No materials listed"
    return (
        "You are IRIS, a concise real-time lab assistant. "
        f"The student is performing {payload.experiment_name} in {payload.subject}. "
        f"Current step {payload.current_step_index}: {payload.current_step}. "
        f"Materials: {materials}. "
        f"Student question: {payload.question}. "
        "Answer in 1-3 short sentences, grounded in the current step."
    )


def build_report_prompt(state: SessionState, payload: CompleteSessionRequest) -> str:
    event_lines = []
    for event in state.events[-25:]:
        details = f"{event.get('type', 'event')}: {event.get('message', '')}"
        if event.get("answer"):
            details += f" | answer: {event['answer']}"
        event_lines.append(details)
    event_block = "\n".join(event_lines) if event_lines else "No events recorded."

    return (
        "You are IRIS, generating a concise lab report refinement.\n"
        f"Experiment: {state.experiment_name}\n"
        f"Subject: {state.subject}\n"
        f"Steps: {state.steps}\n"
        f"Materials: {state.materials}\n"
        f"Existing procedure: {payload.procedure}\n"
        f"Existing observations: {payload.observations}\n"
        f"Existing errors: {payload.errors}\n"
        f"Existing findings: {payload.findings}\n"
        f"Existing suggestions: {payload.suggestions}\n"
        f"Session events:\n{event_block}\n"
        "Return plain text with these labeled sections exactly:\n"
        "SUMMARY:\nOBSERVATIONS:\nFINDINGS:\nSUGGESTIONS:"
    )


async def anthropic_text(prompt: str) -> str | None:
    if not ANTHROPIC_API_KEY:
        return None

    async with httpx.AsyncClient(timeout=25.0) as client:
        response = await client.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": ANTHROPIC_MODEL,
                "max_tokens": 300,
                "messages": [{"role": "user", "content": prompt}],
            },
        )
        response.raise_for_status()
        payload = response.json()

    parts: list[str] = []
    for block in payload.get("content", []):
        if block.get("type") == "text":
            parts.append(block.get("text", ""))
    text = "\n".join(part for part in parts if part).strip()
    return text or None


async def elevenlabs_tts(text: str) -> tuple[str | None, str | None]:
    if not ELEVENLABS_API_KEY or not ELEVENLABS_VOICE_ID:
        return None, None

    async with httpx.AsyncClient(timeout=45.0) as client:
        response = await client.post(
            f"https://api.elevenlabs.io/v1/text-to-speech/{ELEVENLABS_VOICE_ID}",
            headers={
                "xi-api-key": ELEVENLABS_API_KEY,
                "accept": "audio/mpeg",
                "content-type": "application/json",
            },
            json={
                "text": text,
                "model_id": "eleven_multilingual_v2",
                "voice_settings": {
                    "stability": 0.45,
                    "similarity_boost": 0.8,
                },
            },
        )
        response.raise_for_status()
        audio_bytes = response.content

    return base64.b64encode(audio_bytes).decode("utf-8"), "audio/mpeg"


def parse_report_sections(text: str, fallback: CompleteSessionRequest) -> CompleteSessionRequest:
    summary = ""
    observations = fallback.observations
    findings = fallback.findings
    suggestions = fallback.suggestions

    current_label = None
    buckets: dict[str, list[str]] = {"SUMMARY": [], "OBSERVATIONS": [], "FINDINGS": [], "SUGGESTIONS": []}

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        upper = line.rstrip(":").upper()
        if upper in buckets:
            current_label = upper
            continue
        if current_label:
            buckets[current_label].append(line)

    if buckets["SUMMARY"]:
        summary = " ".join(buckets["SUMMARY"])
    if buckets["OBSERVATIONS"]:
        observations = " ".join(buckets["OBSERVATIONS"])
    if buckets["FINDINGS"]:
        findings = buckets["FINDINGS"]
    if buckets["SUGGESTIONS"]:
        suggestions = buckets["SUGGESTIONS"]

    updated = CompleteSessionRequest(
        procedure=fallback.procedure,
        observations=observations,
        errors=fallback.errors,
        findings=findings,
        suggestions=suggestions,
    )
    if summary:
        updated.findings = [summary] + [item for item in updated.findings if item != summary]
    return updated


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/procedures")
def procedures(q: str = Query(default="")) -> dict[str, list[Procedure]]:
    query = q.strip().lower()
    if not query:
        return {"results": CATALOG}

    results = [
        procedure
        for procedure in CATALOG
        if query in procedure.name.lower()
        or query in procedure.subject.lower()
        or query in procedure.description.lower()
    ]
    return {"results": results}


@app.post("/sessions/start", response_model=SessionStartedResponse)
def start_session(payload: StartSessionRequest) -> SessionStartedResponse:
    session_id = str(uuid4())
    state = SessionState(
        id=session_id,
        experiment_name=payload.experiment_name,
        subject=payload.subject,
        steps=payload.steps,
        materials=payload.materials,
        camera_source=payload.camera_source,
    )
    SESSIONS[session_id] = state

    first_step = current_step_text(payload.steps, 1)
    guidance = f"Session started for {payload.experiment_name}. Begin with step 1: {first_step}"
    state.events.append({"type": "session", "message": guidance, "timestamp": utc_now().isoformat()})

    return SessionStartedResponse(sessionId=session_id, status="connected", guidance=guidance)


async def answer_question(payload: QuestionRequest, session_id: str | None) -> QuestionResponse:
    answer = local_answer(
        question=payload.question,
        experiment_name=payload.experiment_name,
        step=payload.current_step,
        materials=payload.materials,
    )

    try:
        llm_answer = await anthropic_text(build_question_prompt(payload))
        if llm_answer:
            answer = llm_answer
    except httpx.HTTPError as error:
        answer = f"{answer} Backend AI fallback used because the LLM request failed: {error.__class__.__name__}."

    audio_base64, audio_mime_type = None, None
    try:
        audio_base64, audio_mime_type = await elevenlabs_tts(answer)
    except httpx.HTTPError:
        audio_base64, audio_mime_type = None, None

    if session_id and session_id in SESSIONS:
        SESSIONS[session_id].events.append(
            {
                "type": "question",
                "message": payload.question,
                "answer": answer,
                "timestamp": utc_now().isoformat(),
            }
        )

    return QuestionResponse(
        answer=answer,
        status="connected",
        sessionId=session_id,
        audioBase64=audio_base64,
        audioMimeType=audio_mime_type,
    )


@app.post("/qa", response_model=QuestionResponse)
async def qa(payload: QuestionRequest) -> QuestionResponse:
    return await answer_question(payload, payload.session_id)


@app.post("/sessions/{session_id}/qa", response_model=QuestionResponse)
async def session_qa(session_id: str, payload: QuestionRequest) -> QuestionResponse:
    if session_id not in SESSIONS:
        raise HTTPException(status_code=404, detail="Session not found")
    return await answer_question(payload, session_id)


@app.post("/sessions/{session_id}/events")
def session_event(session_id: str, payload: SessionEventRequest) -> dict[str, str]:
    if session_id not in SESSIONS:
        raise HTTPException(status_code=404, detail="Session not found")

    SESSIONS[session_id].events.append(
        {"type": payload.type, "message": payload.message, "timestamp": utc_now().isoformat()}
    )
    return {"status": "logged"}


@app.post("/sessions/{session_id}/complete", response_model=CompleteSessionResponse)
async def complete_session(session_id: str, payload: CompleteSessionRequest) -> CompleteSessionResponse:
    if session_id not in SESSIONS:
        raise HTTPException(status_code=404, detail="Session not found")

    state = SESSIONS[session_id]
    final_report = payload

    try:
        llm_report = await anthropic_text(build_report_prompt(state, payload))
        if llm_report:
            final_report = parse_report_sections(llm_report, payload)
    except httpx.HTTPError:
        final_report = payload

    state.report = final_report
    state.events.append(
        {"type": "report", "message": report_summary(final_report), "timestamp": utc_now().isoformat()}
    )
    return CompleteSessionResponse(status="complete", report=final_report, summary=report_summary(final_report))


@app.post("/tts", response_model=TTSResponse)
async def tts(payload: TTSRequest) -> TTSResponse:
    audio_base64, audio_mime_type = await elevenlabs_tts(payload.text)
    return TTSResponse(status="ok", audioBase64=audio_base64, audioMimeType=audio_mime_type)
