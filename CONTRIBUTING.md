# Contributing

Ce document donne une vue rapide de l'architecture, des passes, et des conventions de nommage du projet.

## 1. Structure du projet

```
kairos-dev/
├── bin/
│   ├── cli/          # Exécutables kairos (v1) et kairos_v2
│   └── lsp/          # Serveur LSP kairos-lsp
├── lib/
│   ├── ast/          # Types partagés : AST, fo/fo_ltl, provenance, support
│   ├── automata/     # Génération d'automates depuis les contrats LTL
│   ├── instrumentation/  # Passes IR : production, triplets Hoare, élimination
│   │                     # d'historique, kernel, rendu et visualisation DOT
│   ├── logic/        # Logique FO/LTL : atomes, simplification, temporel
│   ├── lsp_protocol/ # Types du protocole LSP Kairos (sérialisés en JSON)
│   ├── parse/        # Lexer, parser Menhir, dump AST
│   ├── pipeline/     # Orchestration bout-en-bout, engine_service, I/O
│   ├── stages/       # Noms et types de stages de pipeline
│   ├── utils/        # Utilitaires transverses (logging)
│   └── why3/         # Émission Why3, obligations de preuve, diagnostics
├── tests/
│   ├── ok/           # Programmes devant vérifier (*.kairos + *.kobj pré-compilés)
│   └── ko/           # Programmes devant échouer (*__bad_*.kairos + cores *.kobj)
├── vscode/           # Extension VS Code (TypeScript)
└── scripts/
    ├── validate_ok_ko.sh          # Campagne de validation ok/ko
    ├── regenerate_bad_code_suite.py   # Génération des variantes __bad_code
    ├── regenerate_bad_spec_suite.sh   # Génération des variantes __bad_spec
    └── vscode.sh                  # Build + packaging + installation du plugin
```

## 2. Types principaux

- **`fo`** — formule atomique (`FRel`, `FPred`), sans connecteurs booléens.
- **`fo ltl`** — formule LTL+booléenne (`LAtom fo`, `LTrue`, `LFalse`, `LNot`, `LAnd`, `LOr`, `LImp`, `LX`, `LG`, `LW`).
- **`fo_o`** — formule annotée avec provenance et localisation (`value : fo ltl`, `origin`, `oid`, `loc`).

## 3. Pipeline et passes

```
.kairos ──► Parse ──► Pass 3: raw_node
                  ──► Pass 4: annotated_node  (triplets Hoare)
                  ──► Pass 5: verified_node   (élimination d'historique)
                  ──► kernel node_ir          (produit automate × IR)
                  ──► Why3                    (obligations de preuve)
                  ──► Prouveurs (Alt-Ergo, Z3, CVC5...)
```

| Passe | Module | Rôle |
|---|---|---|
| Parse | `lib/parse/` | Lexer + parser Menhir → AST |
| Automata | `lib/automata/` | Automates de sûreté depuis contrats LTL |
| Instrumentation | `lib/instrumentation/frontend.ml` | Dispatch des passes IR |
| IR Production (Pass 4) | `lib/instrumentation/ir_production.ml` | Calcul des triplets Hoare |
| History Elimination (Pass 5) | `lib/instrumentation/history_elimination.ml` | Élimination des variables d'historique |
| Kernel | `lib/instrumentation/product_kernel_ir.ml` | Produit automate × IR vérifié |
| Why3 | `lib/why3/` | Génération des obligations et appels prouveurs |

## 4. Tests

Les tests se trouvent dans `tests/ok/` (programmes corrects) et `tests/ko/` (programmes incorrects).

**Convention de nommage des fichiers ko :**
- `*__bad_code.kairos` — bug dans l'implémentation
- `*__bad_invariant.kairos` — invariant incorrect
- `*__bad_spec.kairos` — spécification incorrecte

**Script de validation :**
```bash
./scripts/validate_ok_ko.sh [repo_root] [timeout_par_goal_s] [mode]
```
Modes disponibles : `legacy` | `with_calls` | `without_calls` | `split`

La partition `with_calls` / `without_calls` est calculée dynamiquement : un fichier est `with_calls` s'il contient une déclaration `import`.

## 5. Visualisation IR (VSCode)

Le plugin expose la commande **"Kairos: Open IR Visualization"** qui génère via `kairos_v2 --dump-ir-dir` et affiche trois graphes DOT par nœud :
- **Annotated** — après calcul des triplets (requires en rouge, ensures en vert)
- **Verified** — après élimination de l'historique
- **Kernel** — produit final envoyé à Why3

## 6. Conventions de nommage

- Dossiers et fichiers : `snake_case`.
- Types : noms explicites (`annotated_node`, `fo_o`, `instrumentation_info`).
- Fonctions : verbe + objet (`build_for_node`, `dump_ir_nodes`).
- Ne jamais réintroduire `FTrue`/`FFalse`/`FNot`/`FAnd`/`FOr`/`FImp` dans le type `fo` — ces constructeurs vivent désormais dans `fo ltl` (`LTrue`, `LFalse`, `LNot`, `LAnd`, `LOr`, `LImp`).

## 7. Règles de contribution

- Ne pas mélanger refactor de nommage et changement fonctionnel dans un même commit.
- Préserver les invariants de traçabilité (origines, IDs d'obligations, spans).
- Ajouter/adapter les tests `tests/ok` et `tests/ko` pour toute évolution de comportement.
- Mettre à jour les `.kobj` pré-compilés si la sérialisation change.

## 8. Validation avant PR

```bash
# 1. Build OCaml
eval $(opam env) && dune build

# 2. Campagne de validation complète
./scripts/validate_ok_ko.sh . 5 legacy
```

## 9. Installation du plugin VSCode

```bash
./scripts/vscode.sh            # build + compile TS + package + install
./scripts/vscode.sh --no-open  # même sans ouvrir VS Code
```

Puis dans VS Code : `Cmd+Shift+P` → **Developer: Reload Window**.

## 10. Où commencer selon le type de changement

| Type de changement | Fichiers concernés |
|---|---|
| Syntaxe / AST | `lib/parse/`, `lib/ast/` |
| Logique FO/LTL | `lib/logic/`, `lib/ast/ast.ml` |
| Passes IR | `lib/instrumentation/` |
| Émission Why3 | `lib/why3/` |
| Orchestration pipeline | `lib/pipeline/` |
| CLI | `bin/cli/` |
| LSP / VSCode | `bin/lsp/`, `lib/lsp_protocol/`, `vscode/src/` |
| Tests | `tests/ok/`, `tests/ko/`, `scripts/validate_ok_ko.sh` |
