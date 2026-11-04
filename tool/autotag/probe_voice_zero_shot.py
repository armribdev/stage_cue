"""Sonde : MuQ-MuLan sait-il séparer chant / instrumental par mots (zéro-shot) ?

Résultat du 2026-11-04 sur 26 morceaux : AUC 0,91 contre la voix Essentia (>= 0,5)
mais sans seuil propre (un piano instrumental dépasse un morceau chanté) ; Essentia
sépare proprement. Conservé pour mémoire : ADR 0029, « Voix et tempo ».
Usage : python probe_voice_zero_shot.py <dossier val_plan.json + ess.json + text_latents>
"""
import json
import os
import sys

import numpy as np
import torch
from muq import MuQMuLan

PROMPTS = [
    "music with a singer singing lyrics", "vocal song with a singing voice", "a song with vocals",
    "instrumental music without vocals", "purely instrumental music, no singing", "instrumental music",
]
D = sys.argv[1]
m = MuQMuLan.from_pretrained("OpenMuQ/MuQ-MuLan-large").eval()
with torch.no_grad():
    V = m(texts=PROMPTS).numpy()
plan = json.load(open(os.path.join(D, "val_plan.json"), encoding="utf-8"))
ess = json.load(open(os.path.join(D, "ess.json"), encoding="utf-8"))
M = np.array([np.mean(t["mono"], 0) for t in plan])
S = M @ V.T
d = S[:, :3].mean(1) - S[:, 3:].mean(1)
for t, x in sorted(zip(plan, d), key=lambda r: -r[1]):
    print("%+.3f  essentia=%.2f  %s" % (x, ess[t["file"]]["voice"], os.path.basename(t["file"])[:50]))
