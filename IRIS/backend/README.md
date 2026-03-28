# IRIS Backend

Local FastAPI backend for the IRIS iOS app.

## Run

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export ANTHROPIC_API_KEY=your_key_here
export ELEVENLABS_API_KEY=your_key_here
export ELEVENLABS_VOICE_ID=your_voice_id_here
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Endpoints

- `GET /health`
- `GET /procedures?q=...`
- `POST /sessions/start`
- `POST /sessions/{session_id}/qa`
- `POST /sessions/{session_id}/events`
- `POST /sessions/{session_id}/complete`
- `POST /qa` for compatibility with the existing iOS client path
- `POST /tts`

## Notes

- This backend still runs without external API keys.
- If `ANTHROPIC_API_KEY` is set, Q&A and report refinement use Anthropic.
- If `ELEVENLABS_API_KEY` and `ELEVENLABS_VOICE_ID` are set, Q&A and `/tts` return synthesized audio as base64 MPEG.
- When those env vars are missing or fail, the backend falls back to deterministic local logic.
