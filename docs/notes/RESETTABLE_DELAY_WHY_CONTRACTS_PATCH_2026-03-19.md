# Note de suivi: patch `why_contracts` pour `resettable_delay`

Date: 2026-03-19
Branche: `debug_ko_green`
Fichier modifie: [`lib/why3/why_contracts.ml`](/Users/fdabrowski/Repos/kairos/kairos-dev/lib/why3/why_contracts.ml)

## Objet du patch

Le patch actuellement garde cherche a conserver davantage de granularite pour les
clauses relationnelles `OriginSafety` ancrees a un
`ClauseAnchorProductStep`.

Avant le patch:
- les clauses noyau compilees gardaient essentiellement `src_state`
- puis elles etaient redistribuees au niveau des helpers Why seulement par etat
  source (`step_from_run`, `step_from_hold`, etc.)

Avec le patch:
- on introduit un type local `compiled_kernel_clause`
- on preserve `anchor_step` quand la clause provient d'un
  `ClauseAnchorProductStep`
- les clauses `OriginSafety` ancrees a un pas produit sont retirees du flux
  global `kernel_post_terms`
- elles sont reinjectees comme postconditions specialisees par transition
  runtime correspondante, via un appariement:
  - meme `src_state`
  - meme `dst_state`
  - meme garde simplifiee

L'intention est purement structurelle:
- ne pas changer le corps execute
- ne pas ajouter d'affectation/instrumentation Why
- ne pas raisonner par moniteur ou ghost state

## Effet observe

Resultats verifies apres patch:
- `dune build` passe
- [`tests/ok/delay_int2.kairos`](/Users/fdabrowski/Repos/kairos/kairos-dev/tests/ok/delay_int2.kairos) reste vert
- [`tests/ok/gated_echo_bundle.kairos`](/Users/fdabrowski/Repos/kairos/kairos-dev/tests/ok/gated_echo_bundle.kairos) reste vert en cible
- [`tests/ok/armed_delay.kairos`](/Users/fdabrowski/Repos/kairos/kairos-dev/tests/ok/armed_delay.kairos) reste vert en cible
- [`tests/ok/resettable_delay.kairos`](/Users/fdabrowski/Repos/kairos/kairos-dev/tests/ok/resettable_delay.kairos) reste `FAILED 1`

Observation importante:
- le patch change bien la forme des VCs
- dans [`/tmp/resettable_delay.vc`](/tmp/resettable_delay.vc), on voit apparaitre
  des `Ensures` supplementaires specialises au cas `reset = 0`
- donc la specialisation par transition est reellement active

Mais:
- cela ne suffit pas a faire passer `resettable_delay`
- a ce stade, le patch n'est ni demontre utile pour le cas cible, ni demontre
  globalement nuisible

## Revert

Si on veut retirer ce patch plus tard, il faut simplement revenir au contenu Git
 de [`lib/why3/why_contracts.ml`](/Users/fdabrowski/Repos/kairos/kairos-dev/lib/why3/why_contracts.ml).

Commande de revert local uniquement pour ce fichier:

```bash
git restore --source=HEAD -- lib/why3/why_contracts.ml
```

Verification apres revert:

```bash
dune build
./scripts/validate_ok_ko.sh . 5 single_ok 60 tests/ok/resettable_delay.kairos
```

Si on veut seulement inspecter ce que le revert enleverait avant de le faire:

```bash
git diff -- lib/why3/why_contracts.ml
```

## Zones exactes touchees

Le patch actuel touche principalement:
- l'ajout du type local `compiled_kernel_clause`
- la preservation de `anchor_step` dans
  `compile_relational_kernel_clause_summary`
- l'extraction des `OriginSafety` ancrees a un pas dans
  `kernel_step_post_clauses`
- la reinjection de ces clauses dans `post` et dans les labels/vcid de post

Repere pratique dans le diff actuel:
- ajout autour de `guard_term_old`
- modification des fonctions
  `compile_relational_kernel_clause_summary` et
  `compile_merged_relational_kernel_clause_summary`
- modification de la construction de `kernel_post_terms`
- ajout du bloc `kernel_step_post_contract_terms`

## Suite: correctif Why-printing

Un second correctif a ensuite ete ajoute, apres avoir elimine une tentative
non fiable basee sur des `if`.

Fichiers modifies:
- [`lib/ast/support.ml`](/Users/fdabrowski/Repos/kairos/kairos-dev/lib/ast/support.ml)
- [`lib/ast/support.mli`](/Users/fdabrowski/Repos/kairos/kairos-dev/lib/ast/support.mli)
- [`lib/why3/why_compile_expr.ml`](/Users/fdabrowski/Repos/kairos/kairos-dev/lib/why3/why_compile_expr.ml)
- [`lib/why3/why_call_plan.ml`](/Users/fdabrowski/Repos/kairos/kairos-dev/lib/why3/why_call_plan.ml)

Objet:
- remplacer les usages sensibles de `Tbinop` pour `/\`, `\/` et `->` par
  `Tbinnop`, via le helper `term_bool_binop`
- etendre les helpers de simplification/pretty-print pour traiter `Tbinnop`
  comme les anciens connecteurs booleens

Motivation:
- le `.kobj` exportait correctement des formules du type
  `(A -> B) /\ (C -> D)`
- mais le Why emis et relu par Why3 affaiblissait certaines de ces formules
  mixtes en raison de l'impression des connecteurs booleens
- `Tbinnop` est l'alternative Why3 utilisee ici pour conserver une impression
  non associative, sans toucher a la semantique ni au corps execute

Effet observe apres ce correctif:
- `dune build` passe
- [`tests/ok/resettable_delay.kairos`](/Users/fdabrowski/Repos/kairos/kairos-dev/tests/ok/resettable_delay.kairos)
  passe en `OK 0`
- replay direct:

```bash
_build/default/bin/cli/main.exe tests/ok/resettable_delay.kairos \
  --dump-proof-traces-json - --proof-traces-failed-only --timeout-s 5
```

retourne `[]`

- les temoins verifies restent verts:
  - [`tests/ok/delay_int2.kairos`](/Users/fdabrowski/Repos/kairos/kairos-dev/tests/ok/delay_int2.kairos)
  - [`tests/ok/gated_echo_bundle.kairos`](/Users/fdabrowski/Repos/kairos/kairos-dev/tests/ok/gated_echo_bundle.kairos)

## Revert du correctif Why-printing

Si on veut retirer uniquement ce second correctif:

```bash
git restore --source=HEAD -- \
  lib/ast/support.ml \
  lib/ast/support.mli \
  lib/why3/why_compile_expr.ml \
  lib/why3/why_call_plan.ml
```

Puis revalider:

```bash
dune build
./scripts/validate_ok_ko.sh . 5 single_ok 60 tests/ok/resettable_delay.kairos
```

## Etat de la recherche apres les deux correctifs

Conclusion de travail actuelle:
- garder le patch `why_contracts` pour la specialisation par pas
- garder le correctif Why-printing base sur `Tbinnop`
- la tentative en `if` a ete retiree et ne doit pas etre reintroduite
