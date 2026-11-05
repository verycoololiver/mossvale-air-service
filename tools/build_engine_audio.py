"""Original, seamless propeller-engine loop; standard-library synthesis only."""
from pathlib import Path
import math
import struct
import wave

out = Path(__file__).resolve().parents[1] / 'game/audio/heron_engine.wav'
rate = 22050
samples = []
for i in range(rate):
    t = i / rate
    pulse = sum(math.sin(2 * math.pi * 48 * h * t) / h**1.3 for h in range(1, 10))
    valve = .15 * math.sin(2 * math.pi * 173 * t) + .07 * math.sin(2 * math.pi * 347 * t)
    samples.append(struct.pack('<h', int(16000 * (pulse + valve) / 1.7)))
with wave.open(str(out), 'wb') as stream:
    stream.setnchannels(1)
    stream.setsampwidth(2)
    stream.setframerate(rate)
    stream.writeframes(b''.join(samples))
print(out)
