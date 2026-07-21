# 0001 — Chargement audio SoLoud : file unique et octets lus côté Dart

**Statut :** acceptée
**Date :** 2026-07-21 *(décision antérieure, consignée rétroactivement)*

## Contexte

flutter_soloud plante sous Windows quand plusieurs `loadMem` partent en parallèle, y compris sur des fichiers différents, et l'ouverture de fichier côté C++ échoue sur les chemins Unicode (accents, NFD). Le même moteur natif est aussi sollicité hors lecture (extraction de waveform, souvent depuis un isolate `compute`).

## Décision

Toute opération SoLoud qui décode un fichier passe par une file d'exécution unique et globale (`_loadMemChain` dans `core/audio/soloud_file_loader.dart`), et les octets sont lus côté Dart (`readAsBytes`) avant d'être remis à `loadMem` avec `LoadMode.memory`.

## Alternatives écartées

- **Laisser SoLoud ouvrir le fichier par son chemin** — échoue sur les chemins Unicode Windows, précisément ceux que produit une bibliothèque Drive avec des noms accentués.
- **Paralléliser les préchargements pour accélérer l'ouverture d'un plateau** — c'est exactement ce qui fait planter le moteur natif sous Windows. Le gain de latence ne vaut pas un crash en représentation.
- **Une file par type d'opération (lecture vs waveform)** — insuffisant : deux accès natifs concurrents plantent quelle que soit leur nature. `enqueueSoLoudFileTask` partage donc délibérément la file de `loadMem`.

## Conséquences

- Ne jamais appeler `SoLoud.instance.loadMem` directement : passer par `loadAudioSourceFromFile`, sinon la sérialisation est contournée et le crash Windows revient.
- Toute nouvelle tâche native décodant un fichier doit être enveloppée dans `enqueueSoLoudFileTask`.
- Conséquence indirecte exploitée ailleurs : les octets étant copiés en mémoire, **supprimer le fichier sur disque ne coupe pas une lecture en cours**. L'éviction LRU ([0010](0010-epinglage-lru-favoris-et-plateau-actif.md)) s'appuie sur cette propriété — la remettre en cause (passage à `LoadMode.disk`) invaliderait la politique d'éviction.
- La file étant globale et sans borne, une tâche qui ne se termine jamais bloque tout l'audio. Toute tâche enfilée doit avoir une sortie garantie.
