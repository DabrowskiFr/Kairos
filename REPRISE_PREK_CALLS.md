# Reprise `pre_k` a travers appels

## Etat au moment de la pause

Contexte:
- Branche: `codex/kairos-kernel-guided-refactor`
- Repo: `/Users/fdabrowski/Repos/kairos/kairos-dev`
- Contrainte forte: rester compositionnel et aligné avec la formalisation
- Proscrit: toute approche moniteur / affectation / instrumentation semantique (`__aut_state`, `ghost ... <- ...`)

Etat general stable:
- le build passe avec `opam exec -- dune build --display short`
- la validation v2 est en place via `scripts/validate_ok_ko.sh` + `bin/dev/prove_v2_json.exe`
- les cas pilotes sans appels sont sains:
  - `delay_int.kairos` -> `OK 0`
  - `resettable_delay.kairos` -> `OK 0`
  - `credit_balance_monitor__bad_code.kairos` n'est plus faux vert dans la voie v2

Etat sur les appels:
- les cas profondeur 1 sont sains:
  - `delay_int_instance.kairos` -> `OK 0`
  - `guarded_delay_instance.kairos` -> `OK 0`
  - `pair_pipeline_guarded.kairos` -> `OK 0`
- les cas profondeur > 1 ne crashent plus sur `relational pre_k depth 1`
- mais ils restent bloques en preuve/perf:
  - `delay_int2_instance.kairos`
  - `delay_int_via_two_calls.kairos`
  - `guarded_double_delay_instance.kairos`

## Ce qui a ete etabli

1. Le caller ne doit pas reprouver le callee.
- la bonne interface est un resume instancie au site d'appel
- il faut composer:
  - `callee_tick_abi`
  - `call_site_instantiations`
  - `instance_relations`

2. Les liens d'historique instancies existent bien.
Pour `delay_int2_instance`, on a verifie:
- `t <- pre(x)`
- `y <- pre(t)`

3. Le Why v2 helper est semantiquement bon.
Avec `bin/dev/emit_why_v2.exe`, on voit dans les helpers:
- `vars.t = old(x)`
- `vars.y = old(vars.t)`

4. Le vrai bug identifie cote appels etait la mauvaise frontiere temporelle du `any` local.
Avant correction, le second call emettait dans le `any`:
- `ensures { (__call_out_d2_0 = old(vars.t)) }`

Dans ce contexte Why, ce `old(vars.t)` etait interprete au niveau local du call et se rabattait
effectivement sur la valeur courante du tick, ce qui redonnait des VCs du style:
- `y = t_courant`

## Correction gardee

Fichier principal:
- [why_call_plan.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.ml)

Correction gardee:
- les `exported_post_facts` temporels qui parlent des sorties du callee ne sont plus reinjectes comme `ensures` du `any` local du call
- ils sont verifies cote caller via les assertions issues des resumes instancies

Verification Why v2:
- avant: `ensures { (__call_out_d2_0 = old(vars.t)) }`
- maintenant: `assert { (__call_out_d2_0 = old(vars.t)) }` apres le call, au niveau caller

Outil ajoute pour le diagnostic:
- [emit_why_v2.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/dev/emit_why_v2.ml)

## Point de blocage restant

Apres cette correction, on n'a plus le faux encodage local evident dans le `any`, mais les cas profonds restent en `TIMEOUT`.

Interpretation actuelle:
- le probleme principal n'est plus une mauvaise semantique flagrante
- le blocage restant est une question de forme des VCs / performance de preuve

Important:
- une tentative de deplacer la notion de "pre-etat de tick caller" via des snapshots globaux dans `why_core.ml` a ete testee puis retiree
- elle n'a pas apporte de correction propre et ne doit pas servir de base de reprise

## Fichiers pertinents pour reprendre

Architecture / emission:
- [why_runtime_view.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml)
- [why_call_plan.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.ml)
- [why_contracts.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml)
- [why_compile_expr.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_compile_expr.ml)
- [why_core.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.ml)

Amont produit / resumes:
- [product_kernel_ir.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml)

Outils de diagnostic:
- [prove_v2_json.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/dev/prove_v2_json.ml)
- [probe_v2_goal.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/dev/probe_v2_goal.ml)
- [emit_why_v2.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/dev/emit_why_v2.ml)

## Commandes utiles

Build:

```sh
opam exec -- dune build --display short
```

Verifier un cas profond:

```sh
KAIROS_WHY_PRODUCT_STEP_MODE=1 ./_build/default/bin/dev/prove_v2_json.exe tests/with_calls/ok/inputs/delay_int2_instance.kairos 5
```

Sortir le Why v2 exact:

```sh
KAIROS_WHY_PRODUCT_STEP_MODE=1 ./_build/default/bin/dev/emit_why_v2.exe tests/with_calls/ok/inputs/delay_int2_instance.kairos > /tmp/delay_int2_instance_v2.why
```

Sonder une VC precise:

```sh
KAIROS_WHY_PRODUCT_STEP_MODE=1 ./_build/default/bin/dev/probe_v2_goal.exe tests/with_calls/ok/inputs/delay_int2_instance.kairos 0
KAIROS_WHY_PRODUCT_STEP_MODE=1 ./_build/default/bin/dev/probe_v2_goal.exe tests/with_calls/ok/inputs/delay_int2_instance.kairos 10
```

## Point de reprise recommande

Ne pas retoucher l'amont `pre_k` ni revenir a une instrumentation runtime.

Reprendre ici:
1. mesurer les goals restantes sur
   - `delay_int2_instance`
   - `delay_int_via_two_calls`
   - `guarded_double_delay_instance`
2. verifier, avec `probe_v2_goal`, que les obligations residuelles portent bien la bonne semantique historique
3. si oui, travailler uniquement la presentation Why / la structuration des VCs cote appels pour reduire le `TIMEOUT`

En une phrase:
- la semantique `pre_k` via appels profonds est beaucoup mieux placee qu'avant
- le prochain chantier n'est plus "corriger le sens", mais "faire prouver la bonne VC sans explosion"
