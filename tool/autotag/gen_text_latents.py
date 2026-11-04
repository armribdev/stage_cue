"""Génère text_latents.f32 : 15 vecteurs texte MuQ-MuLan (15 x 512 float32 little-endian).

L'ORDRE DES LIGNES EST CELUI DE MOODS ci-dessous ; le code Dart
(lib/core/autotag/mood_tagging.dart, kMoods) doit l'utiliser à l'identique.
Usage : python gen_text_latents.py [sortie.f32]   (défaut : assets/autotag/text_latents.f32)
"""
import sys

import numpy as np
import torch
from muq import MuQMuLan

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

out = sys.argv[1] if len(sys.argv) > 1 else "../../assets/autotag/text_latents.f32"
m = MuQMuLan.from_pretrained("OpenMuQ/MuQ-MuLan-large").eval()
with torch.no_grad():
    t = m(texts=[f"{d} music" for d in MOODS.values()]).numpy().astype("<f4")
assert t.shape == (15, 512), t.shape
t.tofile(out)
print("écrit", out, t.shape)
