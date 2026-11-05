"""Small original boot-step samples, synthesized offline with standard Python."""
from pathlib import Path
import math
import random
import struct
import wave

destination = Path(__file__).resolve().parents[1] / 'game' / 'audio'
destination.mkdir(parents=True, exist_ok=True)
rate = 22050
for variation in range(4):
    rng = random.Random(137 + variation)
    filtered = 0.0
    samples = []
    for index in range(int(rate * .18)):
        t = index / rate
        filtered = filtered * .78 + rng.uniform(-1, 1) * .22
        attack = min(t / .004, 1)
        impact = math.sin(math.tau * (87 - 90*t) * t) * math.exp(-t*39) * .36
        grit = filtered * math.exp(-t*24) * .72
        scuff = rng.uniform(-1, 1) * math.exp(-((t-.035)/.024)**2) * .032
        value = max(-1, min(1, (impact + grit + scuff) * attack))
        samples.append(struct.pack('<h', int(value * 32767)))
    with wave.open(str(destination / f'footstep_{variation}.wav'), 'wb') as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(rate)
        sound.writeframes(b''.join(samples))
