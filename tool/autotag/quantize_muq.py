"""Quantifie muq_audio.onnx (fp32, ~1,29 Go) en int8 sur les seuls MatMul (~480 Mo).

Ne PAS quantifier les Conv (le spectrogramme est détruit : n°1 identique 53 %) et ne
pas passer par fp16 (onnxconverter-common produit un graphe invalide).
Usage : python quantize_muq.py   (dans le dossier de muq_audio.onnx)
"""
import os
from onnxruntime.quantization import QuantType, quantize_dynamic

quantize_dynamic(
    "muq_audio.onnx",
    "muq_audio_int8.onnx",
    weight_type=QuantType.QInt8,
    op_types_to_quantize=["MatMul"],
    per_channel=True,
)
print("int8: %.0f Mo" % (os.path.getsize("muq_audio_int8.onnx") / 1e6))
