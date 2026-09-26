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
