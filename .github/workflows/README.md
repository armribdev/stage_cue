# GitHub Actions — Builds de release

Le workflow [`release.yml`](release.yml) compile Stage Cue sur **Android, iOS, macOS, Linux et Windows**.

## Comment le lancer

- **Automatique** : pousser un tag commençant par `v`.
  ```sh
  git tag v1.0.0
  git push origin v1.0.0
  ```
  → build des 5 plateformes + création d'une **GitHub Release** avec tous les artefacts attachés.

- **Manuel** : onglet **Actions** → *Release* → *Run workflow*.
  → les builds tournent et les artefacts sont téléchargeables depuis la page du run (pas de Release créée, car pas de tag).

- **Reconstruire une release existante** (binaires manquants) sans déplacer son tag : créer une branche depuis le tag, y ajouter le correctif nécessaire, la pousser, puis lancer *Run workflow* sur cette branche avec `tag` = `vX.Y.Z` (l'installeur Windows prend ce numéro, le pubspec est vérifié). Joindre ensuite les artefacts à la release avec `gh release upload vX.Y.Z <fichiers>`, puis supprimer la branche et le run.

## ONNX Runtime (Linux et Windows)

`flutter_onnxruntime` télécharge ONNX Runtime depuis `github.com/microsoft/onnxruntime`, dépôt qui renvoie 404 depuis mi-novembre 2026. Les jobs Linux et Windows lancent donc [`tool/fetch_onnxruntime.sh`](../../tool/fetch_onnxruntime.sh) avant `flutter build` : il installe le paquet NuGet officiel (SHA-256 vérifié) là où le plugin le cherche, ce qui lui fait sauter son téléchargement.

- Si une mise à jour de `flutter_onnxruntime` change la version attendue, le script s'arrête en l'indiquant : mettre à jour `plugin_version`, `nuget_version` et `nupkg_sha256` en tête du script.
- Un build local propre (`flutter clean`) échoue pour la même raison : lancer `bash tool/fetch_onnxruntime.sh windows` (ou `linux`) après `flutter pub get`, avec `cmake` dans le PATH.
- À retirer quand le plugin récupère ONNX Runtime ailleurs que sur GitHub.

## Artefacts produits

| Plateforme | Fichier                       | Installable tel quel ?                       |
|------------|-------------------------------|----------------------------------------------|
| Android    | `app-release.apk` + `.aab`    | APK : oui (sources inconnues). AAB : Play Store. |
| iOS        | `app-unsigned.ipa`            | ❌ non — signature Apple requise              |
| macOS      | `stage_cue-macos.zip`         | oui, avec avertissement Gatekeeper            |
| Linux      | `stage_cue-linux-x64.tar.gz`  | oui                                           |
| Windows    | `stage_cue-windows-x64.zip` + `StageCue-Setup-X.Y.Z.exe` | oui, avec avertissement SmartScreen (installeur : voir `windows/installer/stage_cue.iss`) |

## Signature

Les builds ne sont **pas** signés pour distribution « officielle » (certificat Authenticode Windows / keystore Play Store / compte Apple). C’est volontaire tant qu’aucun certificat payant n’est prévu :

- **Windows** — SmartScreen (« éditeur inconnu ») reste affiché ; l’installeur et la mise à jour auto fonctionnent quand même (`lib/core/update/`, `windows/installer/stage_cue.iss`).
- **Android** — APK/AAB signés avec la clé **debug** (OK pour tests, pas pour le Play Store).
- **iOS / macOS** — iOS en `--no-codesign` ; macOS non notarisé (Gatekeeper).

Prévenir les beta-testeurs dans les notes de release (SmartScreen → *Plus d’infos* → *Exécuter quand même*).
