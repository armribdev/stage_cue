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
- **Voix et tempo** (tags `MUSIQUE`) : **non posés pour l'instant.** Mesuré le
  2026-11-04 sur 29 morceaux (têtes Essentia/MTG, ~24 Mo en ONNX). Le **tempo**
  (thèmes MTG `slow` / `fast` / `upbeat`) est inutilisable : probabilités ≈ 0
  partout, un morceau nommé « Très lent » (0,06) ne se distingue pas du reste —
  Lent / Rythmé ne sont donc pas posés automatiquement. La **voix**
  (`voice_instrumental`) sépare proprement (morceaux chantés ≥ 0,75,
  « Instrumental » ≤ 0,22, cohérent avec les noms de fichiers), mais exige un
  front-end audio supplémentaire en Dart (mel 16 kHz, patchs EffNet) et un second
  modèle pour deux tags : **suite documentée, hors de cette décision.** Alternative
  sans modèle de plus, testée : MuQ-MuLan en zéro-shot (« chanté » contre
  « instrumental ») donne AUC 0,91 contre la voix Essentia, mais sans seuil propre
  (un piano instrumental dépasse un morceau chanté) — ne convient pas à un tag
  posé sans validation (`tool/autotag/probe_voice_zero_shot.py`).
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
  tourne donc **après** le pull (`AutoSyncCoordinator`, à la fin de chaque passe, de
  la veille et au retour au premier plan) et un push est planifié quand elle a posé
  des tags. Un pull qui efface les tags d'un son qui en portait rouvre sa décision
  (`auto_tagged_at` remis à `null`, empreinte conservée : aucune ré-analyse du
  fichier), et ses tags sont reposés au passage suivant.
- **Planification** : une passe d'analyse est un passage séparé de la passe de
  synchro (elle dure des minutes et ne doit jamais retenir « Actualiser »). Elle ne
  démarre pas, ou s'arrête entre deux sons, en **Mode Spectacle**, app en
  **arrière-plan** ou **passe de synchro en cours**. Elle tourne aussi en usage 100 %
  local. Le Mode Spectacle n'a pas de signal de sortie : elle reprend au tick de
  veille suivant (≤ 5 min). Le décodage ne tient la file SoLoud que ≈ 100 ms par clip.
  Réservée aux sons de type **musique** (le type en base est la source), non traités,
  sans tag, dont le fichier est **déjà sur l'appareil** ; poste de bureau seulement.
  `sounds.auto_embedding` (v44) garde l'empreinte de chaque son : le recentrage se
  recalcule sans ré-analyser, y compris quand le vocabulaire d'ambiances s'élargit.
- **Règle de pose** : par ambiance, score recentré sur la moyenne **et normalisé par
  l'écart-type** de la bibliothèque analysée ; une ambiance n'est posée qu'à
  **z ≥ 1,0**, **3 tags au plus**, et **rien tant que 50 sons ne sont pas analysés**.
  Les 15 ambiances pointent vers des tags EMOTION_STYLE existants (Merveilleux →
  Magie, Dramatique → Drame, Sensuel → Romantique) ; l'analyse ne crée jamais de tag.
  Le seuil est un choix prudent sur 26 morceaux, sans vérité terrain (ex. « Piano
  triste » z = 0,8 ne reçoit aucun tag) : à recaler sur une bibliothèque plus grande.
  L'éligibilité est **revérifiée au moment de poser** (un son traité ou tagué
  entre-temps est laissé intact). Les écritures locales d'analyse ne déclenchent
  pas de push.
- **Pack** : `muq_audio_int8.onnx` (~480 Mo) est une asset de la GitHub Release
  `autotag-pack-1` du dépôt ; adresse, taille et **SHA-256 sont dans le binaire**
  (`AutoTagPackRelease`), donc une release altérée est refusée. Téléchargé en `.part`,
  vérifié au fil du flux, puis renommé ; annulable ; supprimable depuis Paramètres →
  Analyse automatique, qui affiche l'attribution CC BY-NC. Sans pack, l'analyse ne
  fait rien : l'installer vaut consentement.
- **Origine des tags (point ouvert résolu sans colonne d'origine)** : un son non
  traité qui s'ouvre avec des tags **et** une marque `auto_tagged_at` affiche un
  bandeau « Tags posés automatiquement d'après le son — vérifiez-les, puis validez ».
  Pas d'origine par tag, donc pas de format de snapshot modifié, et pas d'action
  « retirer les tags automatiques » : on retire un tag par sa croix, ou on valide.
  Le bandeau disparaît à la validation (le son devient traité). Limite assumée : des
  tags ajoutés à la main sur un son non traité ailleurs que dans ce formulaire seraient
  couverts par le même bandeau.
- **`flutter_onnxruntime` fournit la bibliothèque native, pas l'API.** Son API Dart
  passe par un canal de plateforme dont le gestionnaire exécute l'inférence sur le
  thread de l'interface (Windows : threads plateforme et Dart fusionnés) : mesuré,
  ≈ 410 ms de gel complet du thread Dart par clip de 10 s, 8 images rendues en
  2,4 s — inacceptable hors Mode Spectacle (un déclenchement de pad attendrait).
  Le paquet est donc gardé pour télécharger et embarquer `onnxruntime` à la
  compilation sur chaque plateforme, mais `OnnxSession` appelle l'API C par FFI
  depuis un isolate de travail (`MuqAnalyzer`) : écart maximal entre deux ticks de
  8 ms pendant l'inférence : 11 ms. Les rangs de la table `OrtApi` viennent de
  `onnxruntime_c_api.h` (ORT 1.28) et ne changent pas entre versions (on demande
  l'API 17). Vérifié sous Windows seulement ; le chargement de la bibliothèque
  est prévu pour Linux et macOS, non éprouvé.
