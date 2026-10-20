# 0026 — Vérification SHA-256 de l'installeur avant lancement de la mise à jour

**Statut :** acceptée
**Date :** 2026-10-20

## Contexte

La mise à jour télécharge `StageCue-Setup-X.Y.Z.exe` depuis la dernière GitHub Release puis le lance en `/VERYSILENT`, sans interaction. Jusqu'ici le seul contrôle était la taille reçue (`Content-Length`) : un fichier de bonne taille mais altéré ou corrompu était exécuté tel quel. L'installeur n'est pas signé (Authenticode écarté tant qu'aucun certificat payant n'est prévu, cf. `.github/workflows/README.md`).

## Décision

L'app compare l'empreinte SHA-256 de l'installeur téléchargé au champ `digest` (`sha256:<hex>`) que l'API GitHub expose pour chaque asset de release. L'empreinte est calculée au fil du flux, et le `.part` n'est renommé (donc l'installeur n'est lançable) que si elle correspond. Sans `digest` exploitable, `AppUpdateChecker` ne propose pas la mise à jour et le journalise (`StageCue.Update`).

## Alternatives écartées

- **Fichier `.sha256` publié par `release.yml`** — ajoute une étape de pipeline et un second asset à tenir synchronisé pour une information que GitHub calcule déjà à l'upload.
- **Signature Authenticode** — seule vraie protection contre une release malveillante et supprime SmartScreen, mais exige un certificat payant. Reste l'option cible si le projet a des utilisateurs hors cercle de confiance.
- **Signature détachée avec clé publique embarquée dans l'app** (minisign, etc.) — protégerait aussi contre une release compromise, sans certificat, mais impose de gérer et protéger une clé de signature. Non retenu pour l'instant.
- **Repli permissif quand le `digest` manque** — rendrait la garde contournable par simple omission du champ ; le refus coûte au pire une mise à jour non proposée.

## Conséquences

- **Ce que ça protège :** un téléchargement corrompu ou altéré en transit ou par un cache/CDN intermédiaire.
- **Ce que ça ne protège pas :** quelqu'un qui peut écrire dans les releases du dépôt. Il publie un nouvel exe, GitHub en calcule le `digest`, et les deux concordent. Cette garde ne remplace donc pas une signature ; elle supprime seulement le cas « exécuter à l'aveugle ».
- Une release sans `digest` (assets uploadés avant l'introduction du champ par GitHub, ou changement de l'API) ne déclenche aucune mise à jour. Si l'API retire le champ, la mise à jour automatique s'arrête silencieusement côté utilisateur : le warning du canal `StageCue.Update` est alors le seul indice.
- `AppUpdateInfo.sha256` est obligatoire : tout nouveau constructeur d'`AppUpdateInfo` (tests compris) doit fournir une empreinte cohérente avec le contenu servi.
- `crypto` est une dépendance directe de `pubspec.yaml` (déjà présente en transitif).
