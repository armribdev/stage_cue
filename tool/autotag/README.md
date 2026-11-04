# Outils du pack d'analyse automatique (ADR 0029)

Scripts Python qui **produisent** les artefacts du pack de modèles (voir
[0029](../../docs/decisions/0029-analyse-automatique-des-tags-sur-l-appareil.md)).
Ils ne sont pas exécutés par l'application.

| Script | Rôle |
| --- | --- |
| `export_muq.py` | Exporte la partie audio de MuQ-MuLan en ONNX (`torch.stft` remplacé par une conv1d DFT équivalente à 3e-6) → `muq_audio.onnx` (fp32, ~1,29 Go) |
| `quantize_muq.py` | Quantification int8 des seuls `MatMul`, par canal → `muq_audio_int8.onnx` (~480 Mo) |
| `gen_text_latents.py` | Vecteurs texte des 15 ambiances → `text_latents.f32` (15 × 512 float32, ~31 Ko, **versionné ici**) |
| `reference_zero_shot.py` | Référence Python (MuQ-MuLan complet, fp32) pour comparer le Dart |
| `validate_ref.py` / `validate_compare.py` | Plan de validation (3 clips à 15/45/75 %) et comparaison Dart ↔ Python |

Dépendances Python : `torch`, `muq`, `onnx`, `onnxruntime`, `librosa`, `soundfile`, `scipy`.

`text_latents.f32` est commité car il est minuscule et fait partie du contrat avec
le code Dart (ordre des moods). Les modèles ONNX, eux, ne le sont jamais (pack
téléchargé). Les JSON de validation (`val_plan.json`, `val_dart.json`) contiennent des
chemins de la bibliothèque personnelle de l'auteur et ne sont pas versionnés : on les
régénère avec `validate_ref.py` sur sa propre liste de fichiers.

SHA-256 du pack de référence (spike du 2026-11-03) :
- `muq_audio_int8.onnx` : `07551cf238af72eee52778f6b8e665efab9f2ad128b3602b635cf215260f6a2a`
- `text_latents.f32` : `de33e54546ec3a03d09ed24aefa60d669c17062ed65011968aac8d1a114343b4`
