# Prompt de reprise Kairos

Travaille dans le dépôt Kairos situé dans `/Users/fredericdabrowski/Repos/kairos/kairos-dev`.

Le chantier en cours concerne le diagnostic d'échec de preuve, la traçabilité de bout en bout, et l'explication de goals Why3/SMT dans l'extension VS Code Kairos.

## Exigences générales

- Ne fais pas de prototype jetable.
- Travaille au niveau production.
- Respecte les conventions du dépôt.
- Maintiens à jour:
  - `/Users/fredericdabrowski/Repos/kairos/kairos-dev/cahier_de_laboratoire.md`
  - `/Users/fredericdabrowski/Repos/kairos/kairos-dev/objectif_methodologie.md`
- Toute modification manuelle de fichier doit se faire avec `apply_patch`.
- Les builds dune doivent être lancés en séquentiel, jamais en parallèle.
- Ne prétends pas que c'est fini si les points restants ne sont pas réellement traités et validés.

## État actuel déjà livré

Le backend, le protocole LSP, la CLI et l'extension VS Code transportent déjà une chaîne de diagnostic structurée pour les proofs:

- traçabilité Source -> OBC -> Why -> VC -> SMT
- `proof_traces` typés
- vue VS Code `Explain Failure`
- dashboard orienté proof failures
- focalisation par goal avec `selected_goal_index`
- séparation `Kairos core` vs `Why3 auxiliary context`
- slicing structurel Why3
- minimisation par replay des hypothèses Kairos instrumentées
- instrumentation Why3 des hypothèses avec `hid`, `hkind`, `origin`
- export CLI JSON des proof traces
- export CLI JSON des unsat cores solveur natifs sur goals ciblés

## État actuel déjà livré pour les cores solveur natifs

Le dépôt contient déjà:

- un chemin `native_unsat_core_for_goal` dans
  `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_prove.ml`
- un export CLI:
  - `--dump-native-unsat-core-json`
  - `--proof-trace-goal-index`
- une exposition LSP/UI des champs:
  - `native_unsat_core_solver`
  - `native_unsat_core_hypothesis_ids`
- une carte `Native Unsat Core` dans `Explain Failure`

Validation déjà faite:

- `delay_int.kairos`, `goal_index 0`:
  - le core solveur natif est récupéré
  - la trace standard l'affiche avec `analysis_method = Native SMT unsat core...`

Limite déjà connue:

- ce core solveur est utile sur une VC `unsat`, pas sur un goal réellement en échec solveur.

## État actuel déjà livré pour les vrais failures

Un premier travail a déjà été fait pour mieux traiter les goals réellement failed:

- une sonde solveur native ciblée par goal a été ajoutée dans
  `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_prove.ml`
- un export CLI dédié existe:
  - `--dump-native-counterexample-json`
  - `--proof-trace-goal-index`
- le diagnostic transporte maintenant:
  - `solver_detail`
  - `native_counterexample_solver`
  - `native_counterexample_model`
- l'UI `Explain Failure` affiche:
  - `Solver Detail`
  - `Native Counterexample`

Builds déjà validés après ces changements:

- `opam exec -- dune build bin/cli/main.exe --display=short`
- `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
- `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
- `cd extensions/kairos-vscode && npm run compile`

Artifacts déjà régénérés:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/docs/kairos_user_manual.pdf`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/extensions/kairos-vscode/kairos-vscode-0.1.2.vsix`

## Limites restantes réelles

### 1. Pas encore de vrai cas `sat`/`invalid` démontré de bout en bout

Le chemin technique de contre-exemple existe, mais il manque encore une validation sérieuse sur un cas réel où:

- le solveur retourne effectivement `sat` sur la négation de la VC
- `model_text` est non nul
- ce modèle est interprétable et utile pour l'utilisateur

Un fixture temporaire a été tenté puis retiré car il n'était pas correct. Il faut donc construire un vrai cas Kairos minimal falsifiable.

### 2. Les vrais `failure` solveur restent souvent opaques

Sur `tests/ok/inputs/delay_int.kairos`, `goal_index 5`, la sonde native retourne encore:

- `status = failure`
- `detail = null`
- `model_text = null`

Donc la catégorisation fine existe, mais ce cas concret reste un `solver_failure` opaque.

### 3. Les cas lourds restent fragiles

`tests/ko/inputs/light_latch.kairos` peut encore déclencher un `Stack overflow` dans certains chemins CLI lourds. Ce point n'est pas fermé.

## Travail à reprendre maintenant

L'objectif prioritaire est:

1. obtenir un vrai contre-exemple solveur natif sur un cas Kairos falsifiable;
2. améliorer l'interprétation des vrais `failure` solveur;
3. stabiliser les cas lourds.

## Ordre de travail impératif

### Étape 1. Produire un vrai cas `invalid`/`sat`

Créer un fixture Kairos minimal dans `tests/ko/inputs/` qui:

- parse correctement avec le frontend v2;
- génère au moins une VC falsifiable;
- permet à Z3 de répondre `sat`;
- permet à `--dump-native-counterexample-json` de renvoyer un `model_text` non nul.

Ne garde le fixture que s'il est correct et réellement utile.

### Étape 2. Valider la remontée complète du modèle

Vérifier explicitement que ce cas remonte correctement:

- en CLI via `--dump-native-counterexample-json`
- dans `--dump-proof-traces-json`
- dans `Explain Failure`

Le diagnostic doit alors passer à:

- `category = counterexample_found`
- `native_counterexample_solver` non nul
- `native_counterexample_model` non nul

### Étape 3. Exploiter mieux `detail` / `reason-unknown` / erreurs solveur

Sur les cas où le solveur ne retourne pas de modèle, améliorer la sonde native pour distinguer:

- `unknown`
- `timeout`
- `solver_error`
- `failure`

Si nécessaire:

- mieux parser la sortie Z3;
- capturer proprement `stderr`;
- distinguer les cas où `get-model` échoue parce que la requête est `unsat` ou parce que le solveur a échoué.

### Étape 4. Stabiliser un cas lourd réel

Reprendre `tests/ko/inputs/light_latch.kairos` et éliminer le `Stack overflow` sur le chemin de diagnostic CLI.

Priorité d'investigation:

- récursions profondes dans la reconstruction de traces;
- sérialisation JSON;
- parcours des tâches Why3;
- minimisation/replay.

### Étape 5. Documentation finale honnête

Mettre à jour:

- `cahier_de_laboratoire.md`
- `objectif_methodologie.md`
- `docs/kairos_user_manual.md`

Puis régénérer:

- `docs/kairos_user_manual.pdf`
- `extensions/kairos-vscode/kairos-vscode-0.1.2.vsix`

## Commandes utiles déjà en place

### Proof traces ciblées

```bash
opam exec -- _build/default/bin/cli/main.exe tests/ok/inputs/delay_int.kairos \
  --dump-proof-traces-json - \
  --proof-trace-goal-index 5 \
  --timeout-s 3
```

### Unsat core solveur natif

```bash
opam exec -- _build/default/bin/cli/main.exe tests/ok/inputs/delay_int.kairos \
  --dump-native-unsat-core-json - \
  --proof-trace-goal-index 0 \
  --timeout-s 3
```

### Sonde contre-exemple solveur native

```bash
opam exec -- _build/default/bin/cli/main.exe tests/ok/inputs/delay_int.kairos \
  --dump-native-counterexample-json - \
  --proof-trace-goal-index 5 \
  --timeout-s 3
```

## Fichiers déjà clés à relire en priorité

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_prove.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_prove.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/pipeline_v2_indep.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/pipeline.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/protocol/lsp_protocol.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/lsp_app.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/bin/cli/cli.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/extensions/kairos-vscode/src/panels.ts`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/extensions/kairos-vscode/src/types.ts`

## Critère de fin honnête

Ne considère pas ce chantier comme terminé tant que les points suivants ne sont pas démontrés:

- au moins un cas `unsat` avec unsat core solveur natif valide;
- au moins un cas `sat` avec contre-exemple solveur natif et `model_text` utile;
- au moins un cas `failure/unknown/timeout` avec catégorisation plus informative qu'un simple `failure`;
- pas de `Stack overflow` sur le cas lourd choisi pour la validation finale;
- documentation et PDF régénérés;
- VSIX régénérée.
