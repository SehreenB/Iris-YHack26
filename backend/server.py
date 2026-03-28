import os
import asyncio
import aiohttp
import cv2
import numpy as np
import overshoot
from dotenv import load_dotenv

load_dotenv()

ESP32_URL = os.getenv("ESP32_CAPTURE_URL", "http://192.168.137.5/capture")
API_KEY = os.getenv("OVERSHOOT_APIKEY")
WIDTH = 800
HEIGHT = 600
INTERVAL = 1.0
FETCH_DELAY = 0.5
RUN_DURATION = 120


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


async def main():
    if not API_KEY:
        print("OVERSHOOT_APIKEY not set in .env")
        return

    client = overshoot.Overshoot(api_key=API_KEY)
    source = overshoot.FrameSource(width=WIDTH, height=HEIGHT)

    stream = await client.streams.create(
        source=source,
        prompt="What do you see in the image in detail?",
        model="Qwen/Qwen3.5-35B-A3B",
        on_result=lambda r: print(f"[result] {r.result}"),
        on_error=lambda e: print(f"[error] {e}"),
        mode="frame",
        interval_seconds=INTERVAL,
        max_output_tokens=50,
    )

    print(f"Stream {stream.stream_id} running — {RUN_DURATION}s")

    async with aiohttp.ClientSession() as session:
        elapsed = 0.0
        while elapsed < RUN_DURATION:
            frame = await fetch_frame(session)
            if frame is not None:
                source.push_frame(frame)
            await asyncio.sleep(FETCH_DELAY)
            elapsed += FETCH_DELAY

    await stream.close()
    await client.close()
    print("Done.")


if __name__ == "__main__":
    asyncio.run(main())