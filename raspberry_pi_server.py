import asyncio
import websockets
import sounddevice as sd
import numpy as np

INPUT_SAMPLE_RATE = 48000
OUTPUT_SAMPLE_RATE = 16000

CHANNELS = 1
FRAME_DURATION_MS = 20

OUTPUT_FRAME_SIZE = int(OUTPUT_SAMPLE_RATE * FRAME_DURATION_MS / 1000)  # 320


async def audio_stream(websocket):
    print("Client connected")

    try:
        with sd.RawInputStream(
            device=0,
            samplerate=INPUT_SAMPLE_RATE,
            dtype="int16",
            channels=CHANNELS,
        ) as mic_stream:

            print("Mic stream started")

            while True:
                # Read a chunk from mic
                data, _ = mic_stream.read(960)  # 20ms at 48k

                audio = np.frombuffer(data, dtype=np.int16)

                # Downsample 48k → 16k
                audio_16k = audio[::3]

                out_bytes = audio_16k.tobytes()

                await websocket.send(out_bytes)

    except Exception as e:
        print("Stream error:", e)

    finally:
        print("Client disconnected")


async def handler(websocket):
    await audio_stream(websocket)


async def main():
    async with websockets.serve(
        handler,
        "0.0.0.0",
        8080,
        max_size=None
    ):
        print("Audio WebSocket server running on port 8080")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
