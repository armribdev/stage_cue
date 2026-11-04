import torch, time, os, math, numpy as np, traceback
import torch.nn as nn, torch.nn.functional as F
from muq import MuQMuLan

class DFTPower(nn.Module):
    """Spectrogramme de puissance par convolution (équivalent à torchaudio Spectrogram power=2,
    center=True, pad reflect, fenêtre de Hann périodique) : exportable en ONNX, sans STFT complexe."""
    def __init__(s, n_fft=2048, hop=240):
        super().__init__()
        s.n_fft, s.hop = n_fft, hop
        k = torch.arange(n_fft // 2 + 1).unsqueeze(1).double(); n = torch.arange(n_fft).unsqueeze(0).double()
        w = torch.hann_window(n_fft, periodic=True).double()
        ang = 2 * math.pi * k * n / n_fft
        s.register_buffer("cos_k", (torch.cos(ang) * w).float().unsqueeze(1))
        s.register_buffer("sin_k", (-torch.sin(ang) * w).float().unsqueeze(1))
    def forward(s, x):
        x = F.pad(x.unsqueeze(1), (s.n_fft // 2, s.n_fft // 2), mode="reflect")
        re = F.conv1d(x, s.cos_k, stride=s.hop); im = F.conv1d(x, s.sin_k, stride=s.hop)
        return re * re + im * im

m = MuQMuLan.from_pretrained("OpenMuQ/MuQ-MuLan-large").eval()
core = m.mulan.audio.model.model               # MuQModel
mel = core.preprocessor_melspec_2048.mel_stft   # torchaudio MelSpectrogram
orig_spec = mel.spectrogram
w = torch.randn(1, 240000) * 0.1
with torch.no_grad():
    a = orig_spec(w); b = DFTPower()(w)
print("spectrogramme: forme", tuple(a.shape), tuple(b.shape), "| max|diff| relatif = %.2e" % ((a - b).abs().max() / a.abs().max()))
class A(nn.Module):
    def __init__(s, mm): super().__init__(); s.m = mm
    def forward(s, w): return s.m.mulan_module.get_audio_latents(w)
wav = torch.randn(1, 240000) * 0.1
with torch.no_grad():
    ref = A(m).eval()(wav)
mel.spectrogram = DFTPower()
a = A(m).eval()
with torch.no_grad():
    new = a(wav)
print("latent torch avant/après remplacement: cosinus = %.6f" % float((ref * new).sum() / ref.norm() / new.norm()))
try:
    t = time.time()
    torch.onnx.export(a, (wav,), "muq_audio.onnx", input_names=["wav"], output_names=["latent"], opset_version=17, dynamo=False)
    sz = os.path.getsize("muq_audio.onnx") / 1e6
    print("EXPORT OK en %.0f s, fichier %.0f Mo" % (time.time() - t, sz))
    import onnxruntime as ort
    s = ort.InferenceSession("muq_audio.onnx", providers=["CPUExecutionProvider"])
    t = time.time(); out = s.run(None, {"wav": wav.numpy()})[0]; dt = time.time() - t
    cs = float((out * new.numpy()).sum() / np.linalg.norm(out) / np.linalg.norm(new.numpy()))
    print("ORT : %.1f s pour 10 s | cosinus ONNX/torch = %.6f" % (dt, cs))
except Exception as e:
    print("EXPORT ÉCHEC:", type(e).__name__, str(e)[:600])
