import asyncio
from typing import Optional

import numpy as np
import sounddevice as sd
import websockets

# =========================
# Audio configuration
# =========================

# Mic comes in at 48kHz, we downsample to 16kHz by 3:1 decimation (48k -> 16k).
INPUT_SAMPLE_RATE = 48000
OUTPUT_SAMPLE_RATE = 16000

CHANNELS = 1
FRAME_DURATION_MS = 20

# 20ms at 48kHz = 960 samples
INPUT_FRAME_SAMPLES = int(INPUT_SAMPLE_RATE * FRAME_DURATION_MS / 1000)  # 960
# 20ms at 16kHz = 320 samples
OUTPUT_FRAME_SAMPLES = int(OUTPUT_SAMPLE_RATE * FRAME_DURATION_MS / 1000)  # 320
OUTPUT_FRAME_BYTES = OUTPUT_FRAME_SAMPLES * 2  # int16 mono

# Device indices can differ per Pi setup. Keep defaults but allow easy edits.
INPUT_DEVICE: Optional[int] = 0
OUTPUT_DEVICE: Optional[int] = None

# =========================
# Queue/buffer configuration
# =========================

# Outgoing mic frames (Pi -> phone)
MIC_QUEUE_MAX_FRAMES = 50  # ~1 second of 20ms frames
# Incoming translated frames (phone -> Pi speaker)
PLAY_QUEUE_MAX_FRAMES = 200  # ~4 seconds of 20ms frames


async def _put_drop_oldest(q: asyncio.Queue, item: bytes) -> None:
    """Put into a bounded asyncio.Queue; if full, drop the oldest frame (FIFO)."""
    try:
        q.put_nowait(item)
    except asyncio.QueueFull:
        try:
            _ = q.get_nowait()
        except asyncio.QueueEmpty:
            pass
        q.put_nowait(item)


def _normalize_frame(frame: bytes) -> bytes:
    """
    Ensure speaker frames are exactly one 20ms chunk (640 bytes at 16kHz PCM16 mono).
    - If larger: truncate (keeps timing stable)
    - If smaller: pad with zeros (silence)
    """
    if len(frame) == OUTPUT_FRAME_BYTES:
        return frame
    if len(frame) > OUTPUT_FRAME_BYTES:
        return frame[:OUTPUT_FRAME_BYTES]
    return frame + (b"\x00" * (OUTPUT_FRAME_BYTES - len(frame)))


async def mic_producer(mic_queue: asyncio.Queue, stop: asyncio.Event) -> None:
    """
    Producer: reads from microphone, downsamples to 16k PCM16, enqueues 20ms frames.
    Buffer requirement: mic audio is kept in a queue to be sent to the mobile.
    """
    try:
        with sd.RawInputStream(
            device=INPUT_DEVICE,
            samplerate=INPUT_SAMPLE_RATE,
            dtype="int16",
            channels=CHANNELS,
            blocksize=INPUT_FRAME_SAMPLES,
        ) as mic_stream:
            print("[Pi] Mic stream started")

            while not stop.is_set():
                data, _ = mic_stream.read(INPUT_FRAME_SAMPLES)
                audio = np.frombuffer(data, dtype=np.int16)

                # Downsample 48k -> 16k (simple decimation).
                audio_16k = audio[::3]

                out_bytes = audio_16k.tobytes()
                # Always enqueue fixed 20ms frames.
                out_bytes = _normalize_frame(out_bytes)
                await _put_drop_oldest(mic_queue, out_bytes)

                # Yield to event loop (sounddevice read is blocking already).
                await asyncio.sleep(0)

    except Exception as e:
        print("[Pi] Mic producer error:", e)
    finally:
        stop.set()
        print("[Pi] Mic producer stopped")


async def mic_sender(websocket, mic_queue: asyncio.Queue, stop: asyncio.Event) -> None:
    """
    Consumer: dequeues mic frames and sends them over the websocket to the phone.
    """
    try:
        while not stop.is_set():
            frame = await mic_queue.get()
            await websocket.send(frame)
    except websockets.ConnectionClosed:
        pass
    except Exception as e:
        print("[Pi] Mic sender error:", e)
    finally:
        stop.set()


async def playback_consumer(play_queue: asyncio.Queue) -> None:
    """
    Consumer: dequeues translated audio frames and plays them on the Pi speaker.
    Buffer requirement: translated audio stays in a queue to be played on speaker.

    This loop never repeats frames: it only plays what it dequeues (no looping).
    """
    raise RuntimeError(
        "Pi speaker playback is disabled in this design. "
        "Translated output should be played on the PHONE speaker."
    )


async def handle_mic_stream(websocket) -> None:
    """
    WebSocket handler on port 8080: Pi -> phone (mic frames).
    The phone connects here and receives continuous 20ms PCM16 16kHz frames.
    """
    print(f"[Pi] Phone connected for MIC stream: path={getattr(websocket, 'path', '')}")

    # Fresh queues per connection avoids stale frames being resent on reconnect.
    mic_queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=MIC_QUEUE_MAX_FRAMES)
    stop = asyncio.Event()

    producer_task = asyncio.create_task(mic_producer(mic_queue, stop))
    sender_task = asyncio.create_task(mic_sender(websocket, mic_queue, stop))

    try:
        await asyncio.wait({producer_task, sender_task}, return_when=asyncio.FIRST_COMPLETED)
    finally:
        stop.set()
        for t in (producer_task, sender_task):
            t.cancel()
        print("[Pi] Phone disconnected (MIC stream)")


async def handle_translation_in(websocket, play_queue: asyncio.Queue) -> None:
    """
    WebSocket handler on port 8081: phone -> Pi (translated audio frames).
    In this design, translated output is played on the PHONE speaker.
    If the phone still sends audio frames (optional), we accept and discard them
    to keep the connection stable and avoid backpressure / loops.
    """
    print(f"[Pi] Phone connected for PLAYBACK stream: path={getattr(websocket, 'path', '')}")

    # Clear any stale buffered audio (kept only for API compatibility).
    try:
        while True:
            play_queue.get_nowait()
    except asyncio.QueueEmpty:
        pass

    received_frames = 0

    try:
        async for message in websocket:
            if isinstance(message, bytes):
                received_frames += 1
                # Discard. (If you later want Pi speaker playback, re-enable queue+consumer.)
            else:
                # Ignore control strings if any.
                continue
    except websockets.ConnectionClosed:
        pass
    except Exception as e:
        print("[Pi] Translation receiver error:", e)
    finally:
        print(f"[Pi] Phone disconnected (PLAYBACK stream). Received frames: {received_frames}")


async def main() -> None:
    play_queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=PLAY_QUEUE_MAX_FRAMES)

    # NOTE: No Pi speaker playback. Phone should play translated output.

    async def mic_server_handler(websocket):
        await handle_mic_stream(websocket)

    async def playback_server_handler(websocket):
        await handle_translation_in(websocket, play_queue)

    async with websockets.serve(mic_server_handler, "0.0.0.0", 8080, max_size=None):
        async with websockets.serve(playback_server_handler, "0.0.0.0", 8081, max_size=None):
            print("[Pi] WebSocket servers running: 8080 (mic->phone), 8081 (phone->pi-discard)")
            await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())

