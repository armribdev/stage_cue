import os, sys, json, numpy as np
from scipy.stats import spearmanr
D = sys.argv[1]
moods = ['Joyeux','Triste','Nostalgique','Épique','Angoisse','Tension','Mystérieux','Romantique','Calme','Merveilleux','Sombre','Énergique','Léger','Dramatique','Sensuel']
T = np.fromfile(D + '/text_latents.f32', 'float32').reshape(15, 512)
plan = json.load(open(D + '/val_plan.json', encoding='utf-8'))
dart = {t['file']: t['dart'] for t in json.load(open(D + '/val_dart.json', encoding='utf-8'))}
M = np.array([np.mean(t['mono'], 0) for t in plan]); L = np.array([np.mean(t['left'], 0) for t in plan])
Dd = np.array([np.mean(dart[t['file']], 0) for t in plan])
names = [os.path.basename(t['file'])[:38] for t in plan]
cos = lambda a, b: (a * b).sum(1) / np.linalg.norm(a, axis=1) / np.linalg.norm(b, axis=1)
def rep(label, A, B, centre):
    SA, SB = A @ T.T, B @ T.T
    if centre: SA, SB = SA - SA.mean(0), SB - SB.mean(0)
    t1 = np.mean(SA.argmax(1) == SB.argmax(1))
    ov = np.mean([len(set(np.argsort(-a)[:3]) & set(np.argsort(-b)[:3])) / 3 for a, b in zip(SA, SB)])
    in3 = np.mean([a.argmax() in set(np.argsort(-b)[:3]) for a, b in zip(SA, SB)])
    sp = np.mean([spearmanr(a, b)[0] for a, b in zip(SA, SB)])
    print(f'{label:34s} {"recentré" if centre else "brut    "} n°1 identique {t1:4.0%} | n°1 dans top3 {in3:4.0%} | recouvrement top3 {ov:4.0%} | Spearman {sp:.3f}')
print('cosinus latent moyen : gauche vs mono %.3f | dart vs gauche %.3f | dart vs mono %.3f (min %.3f)' % (cos(L, M).mean(), cos(Dd, L).mean(), cos(Dd, M).mean(), cos(Dd, M).min()))
for c in (False, True):
    rep('gauche soxr vs mono soxr', L, M, c)
    rep('dart vs gauche soxr', Dd, L, c)
    rep('dart vs mono soxr (cas réel)', Dd, M, c)
SM, SD = (M @ T.T), (Dd @ T.T); SM -= SM.mean(0); SD -= SD.mean(0)
print()
for n, a, b, c in zip(names, SM, SD, cos(Dd, M)):
    print(f'{c:.3f} {n:38s} réf: {", ".join(moods[i] for i in np.argsort(-a)[:3]):42s} dart: {", ".join(moods[i] for i in np.argsort(-b)[:3])}')
