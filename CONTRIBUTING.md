# Contributing

Ce document donne une vue rapide de l'architecture, des passes, et des conventions de nommage du projet.

## 1. Structure du projet

- `lib/frontend/`
  Analyse lexicale/syntaxique et construction de l'AST parsé.
- `lib/core/`
  Types partagés (AST, logique FO/LTL, provenance, stages, utilitaires).
- `lib/middle_end/`
  Passes AST -> AST (génération d'automates, instrumentation, cohérence des contrats).
- `lib/backend/`
  Émission OBC+/Why3/DOT, diagnostics et mapping des obligations.
- `lib/pipeline/`
  Orchestration de bout en bout, exports, callbacks IDE/CLI.
- `bin/`
  Entrées utilisateur (`cli`, IDE).
- `tests/`
  Cas de test `ok` / `ko`.
- `spec/`
  Notes de formalisation et documents d'architecture.

## 2. Pipeline et passes

Ordre conceptuel (AST principal):

1. **Parse** (`frontend`)
2. **Automata generation** (`middle_end/automata_generation`)
   Construit les automates de sûreté à partir des contrats temporels.
3. **Instrumentation** (`middle_end/instrumentation`)
   Injecte obligations/hypothèses locales par transition (GenHyp / GenObl).
4. **Contracts** (`middle_end/contracts`)
   Vérifie et complète la cohérence des contrats utilisateur.
5. **OBC stage** (`backend/obc`)
   Normalisation/émission OBC+.
6. **Why stage** (`backend/why`)
   Génération Why3 et obligations de preuve.
7. **Prove**
   Exécution du prouveur via la couche pipeline/runner.

Notes:

- L'AST de parsing reste une représentation source.
- Les enrichissements de preuve sont portés par les passes middle-end et backend.
- Le mode legacy runtime monitor a été retiré: une seule méthode est supportée.

## 3. Conventions de nommage

### 3.1 Dossiers et fichiers

- Utiliser `snake_case`.
- Préférer des noms orientés intention:
  - `automata_generation`, `instrumentation`, `contracts`, `pipeline`.
- Éviter les tirets dans les chemins (`middle_end`, pas `middle-end`).

### 3.2 Modules / types / fonctions

- Types: noms explicites (ex: `automata_info`, `instrumentation_info`).
- Fonctions: verbe + objet (`build_for_node`, `transform_node_with_info`).
- Variables: privilégier le domaine métier (`instrumentation_updates`, `automata_stage`).
- Éviter les noms historiques ambigus (`monitor_*`) pour tout nouveau code.

### 3.3 Stages et labels

- Stage AST: `parsed`, `automaton`, `instrumentation`, `contracts`, `obc`.
- `monitor` peut rester accepté comme alias d'entrée si nécessaire pour compatibilité CLI, mais ne doit plus être utilisé comme nom canonique en interne.

## 4. Règles de contribution

- Ne pas mélanger refactor de nommage et changement fonctionnel dans un même commit, sauf demande explicite.
- Préserver les invariants de traçabilité (origines, IDs d'obligations, spans).
- Ajouter/adapter les tests `tests/ok` et `tests/ko` pour toute évolution de comportement.
- Mettre à jour `spec/` quand une transformation de pipeline est modifiée.

## 5. Validation minimale avant PR

Exécuter au minimum:

```bash
dune build
```

Puis vérifier les programmes de référence:

```bash
for f in tests/ok/inputs/*.kairos; do
  dune exec -- kairos --log-level quiet --prove "$f"
done
```

Optionnel (quand pertinent):

```bash
dune runtest
```

## 6. Où commencer selon le type de changement

- Changement syntaxe/AST: `lib/frontend`, `lib/core/ast`.
- Changement logique de passes: `lib/middle_end/*`.
- Changement obligations Why3: `lib/backend/why`.
- Changement exports/CLI/IDE: `lib/pipeline`, `bin/cli`, `bin/ide`.

## 7. Documentation à maintenir

- `README.md` pour la vue utilisateur.
- `spec/formalization_pure_automate.md` pour la sémantique/formalisation.
- `spec/ARCHITECTURE.md` pour la vue composants et pipeline.
