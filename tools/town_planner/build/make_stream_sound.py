"""Make the soundscape's brook: a soft, seamless 30 s mono loop of a small stream, synthesised (no
recording of one is in the project).

usage: python tools/town_planner/build/make_stream_sound.py <project> [seed]

Writes world/audio/soundscape/stream.ogg (Vorbis, 44.1 kHz mono, about -28 dBFS RMS like the other loops),
which world/audio/soundscape.gd plays at the rivers near the listener. Godot imports it on the next editor
start or `godot --headless --path <project> --import`; soundscape.gd turns looping on in code.

The sound, quietest last:
- the body: noise band-passed 250-1100 Hz, swelling and settling slowly (several minutes of no two
  seconds alike would need a recording; slow random swells keep 30 s from sounding like a loop);
- the wash: noise band-passed 1.1-3 kHz, a soft continuous sheen that breathes over a few seconds;
- a faint low murmur under it all (90-260 Hz).
Play test 2026-11-16 ("a bubbling kind of water droplet sound, which I don't really like"): the
bubbles (short sine chirps gliding up an octave) are gone, and the trickle is no longer gated into
short puffs (each puff read as a plink); the wash replaces it, moving only on slow envelopes (nothing
faster than about one change a second), so the brook is a smooth flowing hiss.
No broadband hiss: every layer is band-limited and the top above 4.5 kHz is rolled off. The last two
seconds are crossfaded (equal power) into the first two so the loop has no seam. RMS is set to the
same -28 dBFS as before, so the in-game level is STREAM_DB in world/audio/soundscape.gd alone.
"""
import os, sys
import numpy as np
import soundfile as sf
from scipy import signal

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 7
SR = 44100
LOOP = 30.0
FADE = 2.0
N = int(SR * LOOP)
M = N + int(SR * FADE)
rng = np.random.default_rng(SEED)
t = np.arange(M) / SR


def band(lo: float, hi: float) -> np.ndarray:
    sos = signal.butter(4, [lo, hi], btype="bandpass", fs=SR, output="sos")
    return signal.sosfiltfilt(sos, rng.standard_normal(M))


def drift(rate: float, depth: float) -> np.ndarray:
    """A slow random envelope around 1: smoothed noise with features about 1/rate seconds long."""
    k = max(2, int(M / SR * rate * 4))
    knots = rng.standard_normal(k)
    env = np.interp(np.linspace(0, k - 1, M), np.arange(k), knots)
    env = signal.sosfiltfilt(signal.butter(2, rate, fs=SR, output="sos"), env)
    env /= np.abs(env).max() + 1e-9
    return np.clip(1.0 + depth * env, 0.05, None)


def unit(x: np.ndarray) -> np.ndarray:
    return x / (np.sqrt((x ** 2).mean()) + 1e-12)


body = unit(band(250, 1100)) * drift(0.25, 0.35) * drift(0.8, 0.2)
# the wash: continuous, breathing slowly (a gate of short puffs here read as droplets)
wash = unit(band(1100, 3000)) * drift(0.3, 0.35) * drift(0.9, 0.15)
murmur = unit(band(90, 260)) * drift(0.2, 0.3)

mix = 1.0 * body + 0.28 * wash + 0.5 * murmur
mix = signal.sosfiltfilt(signal.butter(2, 4500, btype="lowpass", fs=SR, output="sos"), mix)
mix = signal.sosfiltfilt(signal.butter(2, 70, btype="highpass", fs=SR, output="sos"), mix)

# seamless: the tail beyond LOOP fades into the head (equal power for uncorrelated noise)
F = M - N
w = np.linspace(0.0, 1.0, F)
out = mix[:N].copy()
out[:F] = mix[:F] * np.sqrt(w) + mix[N:] * np.sqrt(1.0 - w)

rms_db = -28.0
out *= 10 ** (rms_db / 20) / np.sqrt((out ** 2).mean())
peak = np.abs(out).max()
if peak > 0.5: out *= 0.5 / peak
path = os.path.join(ROOT, "world/audio/soundscape/stream.ogg")
# in blocks: libsndfile's Vorbis encoder overflows its stack on one long write
with sf.SoundFile(path, "w", SR, 1, format="OGG", subtype="VORBIS") as f:
    for i in range(0, N, 4096): f.write(out[i:i + 4096].astype(np.float32))
print(f"stream: {LOOP:.0f} s, RMS {20 * np.log10(np.sqrt((out ** 2).mean())):.1f} dBFS, peak {20 * np.log10(np.abs(out).max()):.1f} dBFS -> {path}")
