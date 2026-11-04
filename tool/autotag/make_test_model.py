"""Génère test/fixtures/autotag/double.onnx : y = 2 * x, entrée 'wav' [1, 8], sortie 'latent'.

Modèle minuscule pour tester OnnxSession sans le pack de 480 Mo.
Usage : python make_test_model.py <sortie.onnx>
"""
import sys

import onnx
from onnx import TensorProto, helper

x = helper.make_tensor_value_info("wav", TensorProto.FLOAT, [1, 8])
y = helper.make_tensor_value_info("latent", TensorProto.FLOAT, [1, 8])
two = helper.make_tensor("two", TensorProto.FLOAT, [1], [2.0])
graph = helper.make_graph(
    [helper.make_node("Mul", ["wav", "two"], ["latent"])], "double", [x], [y], initializer=[two]
)
model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
model.ir_version = 8
onnx.checker.check_model(model)
onnx.save(model, sys.argv[1] if len(sys.argv) > 1 else "double.onnx")
