"""MuQ-MuLan zero-shot : ambiances sur les musiques. Lecture seule. Sortie : JSON."""
import json, sys, pathlib
import librosa, torch
from muq import MuQMuLan

lst, out = sys.argv[1], sys.argv[2]
paths = [l for l in pathlib.Path(lst).read_text(encoding="utf-8").splitlines() if l.strip()]

MOODS = {  # tag FR -> description EN
    "Joyeux": "joyful cheerful happy", "Triste": "sad sorrowful",
    "Nostalgique": "nostalgic wistful", "Épique": "epic heroic grand",
    "Angoisse": "anxious dread fearful", "Tension": "tense suspenseful",
    "Mystérieux": "mysterious enigmatic", "Romantique": "romantic tender loving",
    "Calme": "calm peaceful relaxing", "Merveilleux": "magical wondrous dreamy",
    "Sombre": "dark ominous", "Énergique": "energetic driving upbeat",
    "Léger": "lighthearted playful fun", "Dramatique": "dramatic intense emotional",
    "Sensuel": "sensual seductive smooth",
}
mulan = MuQMuLan.from_pretrained("OpenMuQ/MuQ-MuLan-large").eval()
with torch.no_grad():
    t = mulan(texts=[f"{d} music" for d in MOODS.values()])

res = {}
for i, p in enumerate(paths, 1):
    try:
        dur = librosa.get_duration(path=p)
        wav, _ = librosa.load(p, sr=24000, mono=True, offset=15 if dur > 60 else 0, duration=30)
        with torch.no_grad():
            a = mulan(wavs=torch.tensor(wav).unsqueeze(0))
            sim = mulan.calc_similarity(a, t)[0]
        res[p] = dict(zip(MOODS, map(float, sim)))
    except Exception as e:
        print("!", pathlib.Path(p).name, e, flush=True)
    print(f"{i}/{len(paths)}", end="\r", flush=True)
json.dump(res, open(out, "w", encoding="utf-8"), ensure_ascii=False)
print("\nOK", len(res))
