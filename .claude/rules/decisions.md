# Journal de décisions (ADR)

- Avant de proposer un changement d'architecture, de state management, de schéma DB, ou de convention établie dans `CLAUDE.md`/`.claude/rules/` : vérifier `docs/decisions/` pour voir si une décision existante couvre déjà le sujet — ne pas la contredire sans le signaler explicitement à l'utilisateur.
- Après qu'une décision structurante a été prise avec l'utilisateur (voir critères dans `docs/decisions/README.md`) : créer une entrée `docs/decisions/NNNN-titre.md` à partir de `docs/decisions/template.md`, et l'ajouter à l'index dans `docs/decisions/README.md`.
- Ne pas créer d'entrée pour un bugfix, un refactor local, ou un choix qui découle naturellement des conventions déjà écrites — seulement pour ce qui écarte une alternative ou introduit une contrainte durable non-évidente.
- Une entrée remplacée doit être marquée `remplacée par NNNN` plutôt que supprimée — l'historique du "pourquoi" a de la valeur même quand la décision change.
