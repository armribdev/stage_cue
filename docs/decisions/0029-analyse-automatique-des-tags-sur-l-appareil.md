# 0029 — Analyse automatique des tags, sur l'appareil, par modèles ONNX en pack optionnel

**Statut :** acceptée
**Date :** 2026-11-04

## Contexte

Tagger à la main une bibliothèque de sons est long, alors que la recherche ne
repose que sur les tags ([docs/tags.md](../tags.md)). On veut poser des tags
automatiquement à partir de l'audio, pour **n'importe quel utilisateur**
(hors-ligne backstage, sans compte ni service externe), sans alourdir
l'installation et sans que l'utilisateur ait à fournir des exemples
d'entraînement.

## Décision

Analyser les sons **sur l'appareil** avec des modèles embarqués au format
ONNX, exécutés par `flutter_onnxruntime` (MIT, Windows/macOS/Linux/Android/iOS),
livrés en **pack téléchargeable optionnel** (vérifié par SHA-256, comme
l'installeur — [0026](0026-verification-sha256-de-l-installeur.md)), jamais dans
le binaire.

- **Ambiance musicale** (tags `EMOTION_STYLE`) : MuQ-MuLan (partie audio
  seule, quantifiée int8 sur les seuls `MatMul`, ~480 Mo). Les mots
  (« Triste », « Angoisse »…) sont comparés à des vecteurs texte précalculés
  (15 × 512 flottants, ~31 Ko) : aucun encodeur texte à l'exécution.
- **Voix et tempo** (tags `MUSIQUE`) : têtes Essentia/MTG converties en ONNX
  (~24 Mo). La voix (Chant / Instrumental) vient de la tête
  `voice_instrumental` ; le tempo (Lent / Rythmé) se dériverait des thèmes MTG
  `slow` / `fast` / `upbeat`, **sans qualité mesurée à ce jour** : à valider
  avant de poser ces tags automatiquement.
- **Les tags sont appliqués directement**, pas proposés. Le son **reste « non
  traité »** (`isProcessed = false`) jusqu'à ce que l'utilisateur valide ou
  retire les tags. L'analyse ne touche **jamais** un son déjà traité ni un
  son qui porte déjà des tags.
- `sounds.auto_tagged_at` (v43, nullable) marque les sons déjà analysés, même
  quand rien n'a été posé, pour ne pas les ré-analyser. Annotation locale,
  absente du snapshot, comme `is_processed`.

## Alternatives écartées

- **Suggestions à valider** plutôt que tags posés — refusé par l'utilisateur ;
  le statut « non traité » joue ce rôle de validation.
- **Entraîner sur les sons de l'utilisateur** — il n'en aura pas assez, les
  tags seraient mauvais ; on prend des modèles qui ont fait leurs preuves.
- **Outil Python séparé / service distant** — inaccessible à un utilisateur
  quelconque et incompatible avec l'usage hors-ligne.
- **Essentia seul** — bon sur un vocabulaire fixe, mais pas de vocabulaire libre :
  ajouter une ambiance = réentraîner. MuQ-MuLan apporte le zéro-shot par mots.
  (Sur MTG-Jamendo il ne bat pas Essentia en précision pure : on ne le prend
  pas pour la précision.)
- **YAMNet** (14 Mo) — trop faible sur les bruitages. **AST** (~350 Mo) meilleur
  mais lourd. **CLAP**, **MERT**, **CLaMP 3** — plus lourds, non retenus ou non
  testés. Le modèle des bruitages reste **à trancher** (EfficientAT à tester,
  sinon AST en pack séparé) : cette décision ne couvre que la musique.
- **Décodeur audio natif ou ffmpeg en plus** — nouvelle dépendance lourde ;
  on détourne SoLoud (ci-dessous).

## Conséquences

- **Licence : usage non commercial uniquement.** Les têtes Essentia/MTG sont
  CC BY-NC-SA 4.0 et les poids MuQ-MuLan CC BY-NC. Toute commercialisation de
  l'application impose de retirer le pack ou d'obtenir des licences. Attribution
  à afficher dans l'écran de téléchargement du pack. C'est la contrainte durable
  de cette décision.
- **Décodage via le moteur natif de SoLoud, détourné.** Le décodeur d'échantillons
  de flutter_soloud n'est pas un décodeur PCM : avec un nombre d'échantillons égal
  au nombre exact de trames de la fenêtre (pas de 1) et `average: false`, il
  renvoie le **canal gauche seul**, à la **fréquence native** du fichier, qu'il
  faut rééchantillonner soi-même vers 24 kHz (sinc fenêtré polyphasé, en isolate ;
  `average: true` renvoie un RMS, inutilisable). Ce comportement n'est pas un
  contrat du paquet : `test/core/autotag/pcm_decoder_test.dart` échoue s'il change
  (canal, fréquence, décalage, mono, mp3/flac/ogg/wav). La fréquence native et la
  durée ne sont pas exposées (ni stockées en base) : elles sont lues dans l'en-tête
  (`audio_stream_info.dart`). Opus et m4a ne sont pas analysables (le décodeur
  d'échantillons ne lit les Ogg qu'avec libvorbis ; m4a n'est pas un format du
  moteur) : ils sont sautés avec une raison journalisée.
  **On appelle le symbole natif `readSamplesFromFile` directement (FFI) et non
  `SoLoud.readSamplesFromMem/File`** : l'API Dart ne libère jamais ses tampons
  natifs (mesuré : ≈ 10 Mo perdus par appel sur un mp3 de 3 Mo, vérifié sur
  flutter_soloud 4.0.12 et 4.1.7 — plusieurs Go sur une bibliothèque entière). Les
  appels directs gardent la mémoire plate (≈ 0,24 s et aucune croissance par
  piste). Tout décodage reste sérialisé sur la file unique
  ([0001](0001-chargement-audio-soloud.md)). Si flutter_soloud corrige un jour la
  fuite, on pourra revenir à son API.
- **Entrée du modèle** : 3 clips de 10 s (à 15 / 45 / 75 % de la durée), latents
  moyennés. Les scores bruts sont biaisés par mood : **recentrer chaque mood sur
  la bibliothèque** avant tout seuil, et n'appliquer aucun tag tant qu'un nombre
  minimal de sons (de l'ordre de 50) n'a pas été analysé. Poser peu de tags
  (2-3 moods maximum), avec seuil conservateur.
- **Validité mesurée** (26 mp3, Dart contre référence Python mono) : n°1
  identique 92 %, n°1 dans le top-3 de la référence 100 %, recouvrement du
  top-3 91 % après recentrage (81 % / 96 % / 87 % sans). Coût ≈ 0,9 s par clip,
  ≈ 2,6 s par piste, en arrière-plan. Formats non-mp3, pistes mono et mobile
  **non testés** ; 480 Mo en mémoire exclut probablement le mobile.
- **Synchro Drive** : le pull remplace les `sound_tags` d'un dossier par ceux du
  distant ([0003](0003-snapshots-par-dossier-et-fusion-board-par-board.md)). L'analyse
  tourne donc **après** le pull, puis publie ; si un pull réécrit les tags d'un
  dossier, remettre `auto_tagged_at` à `null` pour les sons qui n'ont plus de
  tag, sinon ils ne seraient jamais ré-analysés.
- **Jamais en Mode Spectacle** ni pendant un déclenchement : suspendue comme la
  veille Drive ([0022](0022-veille-drive-en-cours-de-session.md)), dans un isolate dédié.
  Réservée aux sons de type musique (le type en base est la source).
- **Point ouvert** : `sound_tags` n'a pas de colonne d'origine, donc impossible
  de distinguer un tag posé par le modèle d'un tag posé à la main sur un son
  encore non traité. Un « retirer les tags automatiques » ne doit pas supprimer
  les tags manuels : soit on ne l'offre que sur un son jamais édité, soit on
  ajoute une origine (ce qui touche le format du snapshot — décision à part).
- Ajouter `flutter_onnxruntime` à `pubspec.yaml` lors de l'implémentation, pas
  avant : cette entrée l'autorise, la migration v43 ne l'exige pas.
