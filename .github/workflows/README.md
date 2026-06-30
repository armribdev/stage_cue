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
| iOS        | `app-unsigned.ipa`            | ❌ non — signature requise (voir ci-dessous)  |
| macOS      | `stage_cue-macos.zip`         | oui, avec avertissement Gatekeeper            |
| Linux      | `stage_cue-linux-x64.tar.gz`  | oui                                           |
| Windows    | `stage_cue-windows-x64.zip`   | oui, avec avertissement SmartScreen           |

## Signature (à faire plus tard)

Les builds actuels ne sont **pas signés** pour distribution officielle. Pour passer à des
artefacts publiables, il faudra ajouter des **GitHub Secrets** (Settings → Secrets and
variables → Actions) et adapter `release.yml`.

### Android (pour publier sur le Play Store)
1. Générer une keystore :
   `keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Encoder en base64 et créer les secrets : `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
   `KEY_ALIAS`, `KEY_PASSWORD`.
3. Configurer `android/key.properties` + `android/app/build.gradle` (signingConfigs).

### iOS / macOS (compte développeur Apple payant requis)
1. Certificat de distribution + provisioning profile depuis le compte Apple Developer.
2. Secrets : `APPLE_CERT_BASE64`, `APPLE_CERT_PASSWORD`, `PROVISIONING_PROFILE_BASE64`.
3. Importer dans le trousseau du runner puis `flutter build ipa` (sans `--no-codesign`).
   La notarisation macOS demande en plus un mot de passe d'app Apple ID.

### Windows / Linux
Optionnel : signature de code (certificat EXE) ou packaging `.msix` / `.deb` / AppImage.
