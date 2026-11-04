import os, json, sys, numpy as np, soundfile as sf, librosa, onnxruntime as ort
D = sys.argv[1]
files = [l.strip() for l in open(D + '/music_files.txt', encoding='utf-8') if l.strip()]
sess = ort.InferenceSession(D + '/muq_audio_int8.onnx', providers=['CPUExecutionProvider'])
def lat(pcm):
    return sess.run(None, {'wav': pcm.astype('float32')[None, :240000]})[0].reshape(-1)
plan = []
for f in files:
    try:
        i = sf.info(f)
    except Exception as e:
        print('skip', f, e); continue
    dur = i.duration
    if dur < 40: print('skip court', dur, f); continue
    starts = [int(dur * p) for p in (0.15, 0.45, 0.75)]
    mono, left = [], []
    for s in starts:
        x, sr = sf.read(f, start=s * i.samplerate, frames=10 * i.samplerate, dtype='float32', always_2d=True)
        m = librosa.resample(x.mean(1), orig_sr=sr, target_sr=24000, res_type='soxr_hq')[:240000]
        l = librosa.resample(x[:, 0], orig_sr=sr, target_sr=24000, res_type='soxr_hq')[:240000]
        mono.append(lat(m).tolist()); left.append(lat(l).tolist())
    plan.append(dict(file=f, sr=i.samplerate, ch=i.channels, dur=dur, starts=starts, mono=mono, left=left))
    print('ok', i.samplerate, i.channels, round(dur), os.path.basename(f)[:50])
json.dump(plan, open(D + '/val_plan.json', 'w', encoding='utf-8'))
