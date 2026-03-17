# Handoff `Prove` / suppression de la voie automate

## Contexte

- Repo: `/Users/fdabrowski/Repos/kairos/kairos-dev`
- Branche de travail: `codex/kairos-kernel-guided-refactor`
- Demande forte de l'utilisateur:
  - ne pas utiliser d'approche moniteur / automate comme support de preuve
  - ne pas reintroduire `__aut_state`, `Aut0`, `Aut1`, etc.
  - rester aligne avec la formalisation

## Diagnostic de fond

Le chemin `VS Code -> kairos-lsp -> engine_service -> Pipeline_v2_indep.run` utilise bien la pipeline v2.

Le retour des automates dans `Prove` ne venait donc pas d'un fallback legacy du plugin, mais de la pipeline de preuve elle-meme:

- l'etage `OBC Clean` etait insuffisant:
  - il enlevait les contrats/coherency, mais pas toute l'instrumentation moniteur
- le backend Why recompilait encore des clauses kernel avec:
  - `FactGuaranteeState`
  - `OriginInitAutomatonCoherence`
  - `OriginPropagationAutomatonCoherence`

Consequence visible:
- `Prove` en VS Code echouait sur des erreurs du style:
  - `unbound program function or variable symbol 'Aut0'`

## Ce qui a ete etabli de facon fiable

### 1. Le symptome `Aut0` etait reel et reproductible

Cas minimal:
- `tests/with_calls/ok/inputs/delay_core.kairos`

Reproduction:
- `bin/dev/emit_why_raw.exe` montrait un Why avec:
  - `match vars.__aut_state with | Aut0 -> ...`
  - mais parfois un `type aut_state` incomplet

### 2. Le `OBC Clean` courant peut etre rendu propre

Un outil de debug a ete ajoute:
- [emit_obc_v2.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/dev/emit_obc_v2.ml)

Verification utile:
- sur `delay_core.kairos`, `emit_obc_v2.exe` montre un OBC propre:
  - pas de `__aut_state`
  - pas de `Aut0`
  - seulement `locals z, __pre_k1_x`

Donc:
- l'etat moniteur n'est pas semantiquement necessaire a cet etage
- la reintroduction se fait plus bas, au moment de la construction Why / contrats kernel

### 3. La voie `emit_why_raw` a ete nettoyee au moins partiellement

Apres les derniers changements, sur `delay_core.kairos`:
- `emit_why_raw.exe ... | rg "__aut_state|Aut[0-9]+"`
- ne retourne plus rien

Donc le symptome `Aut0` a ete effectivement coupe sur cette voie.

## Modifications locales deja faites

### Pipeline v2

Fichier principal:
- [pipeline_v2_indep.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/pipeline_v2_indep.ml)

Ajouts importants:
- nettoyage du programme OBC utilise pour la preuve:
  - `strip_monitor_node_for_proof`
  - suppression de `__aut_state`, `Aut*`, statements de moniteur dans les transitions
- nettoyage des clauses kernel exportees pour la preuve:
  - suppression de `FactGuaranteeState`
  - suppression des clauses `OriginInitAutomatonCoherence`
  - suppression des clauses `OriginPropagationAutomatonCoherence`
- `why_pass` et `obligations_pass` ne passent plus par `Io.emit_why`, mais reconstruisent le Why via:
  - `Emit.compile_program_ast`
  - avec `kernel_ir_map` et `external_summaries` sanitizes pour la preuve

### Outils dev ajoutes

- [emit_obc_v2.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/dev/emit_obc_v2.ml)
- [emit_why_raw.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/dev/emit_why_raw.ml)
- [emit_why_v2.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/dev/emit_why_v2.ml)
- [prove_v2_json.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/dev/prove_v2_json.ml)

### VS Code

Le workspace pointe maintenant vers le LSP rebuild du repo:
- [settings.json](/Users/fdabrowski/Repos/kairos/kairos-dev/.vscode/settings.json)
  - `kairos.lsp.serverPath = /Users/fdabrowski/Repos/kairos/kairos-dev/_build/default/bin/lsp/kairos_lsp.exe`

## Etat actuel reel

### Ce qui semble vrai

- le symptome `Aut0` a ete retire de la voie `emit_why_raw` sur le cas minimal `delay_core`
- le `OBC Clean` de `delay_core` est bien sans automate
- le plugin VS Code est bien branche sur la pipeline v2 et sur le LSP local rebuild

### Ce qui n'est PAS encore stabilise

- je n'ai pas rerun une campagne complete `without_calls` / `with_calls` apres ces derniers changements
- les rapports `_build/validation/*.tsv` encore presents dans le repo correspondent a un etat plus ancien et sont donc stale pour cette partie
- il reste des problemes sur les historiques `__pre_k*`
  - ex. `unbound function or predicate symbol '__pre_k1_x'`
- le dernier `prove_v2_json.exe delay_core.kairos` ne s'est pas termine avec un resultat consolide exploitable dans ce tour
  - beaucoup de warnings `old`
  - pas de classification finale synthétisée ici

## Point de reprise recommande

### Priorite immediate

Verifier que la suppression de la voie automate tient vraiment sur toute la preuve, pas seulement sur `emit_why_raw`.

Ordre recommande:

1. Reinstaller/recharger l'environnement de test:
   - `./scripts/vscode.sh --no-open`
   - puis `Developer: Reload Window` dans VS Code

2. Verifier la regression cible:
   - ouvrir `tests/with_calls/ok/inputs/delay_core.kairos`
   - lancer `Kairos: Prove`
   - confirmer que l'erreur `Aut0` / `__aut_state` n'apparait plus

3. Refaire les checks CLI minimaux:
   - `emit_obc_v2.exe delay_core.kairos`
   - `emit_why_raw.exe delay_core.kairos | rg "__aut_state|Aut[0-9]+"`
   - `prove_v2_json.exe delay_core.kairos 5`

4. Seulement ensuite, attaquer le prochain vrai bug:
   - `__pre_k1_x` non lie dans certains cas

### Regle architecturale a garder

Ne pas "reparer" la branche automate.

Si un endroit de la voie `Prove` reintroduit:
- `__aut_state`
- `Aut0`, `Aut1`, ...
- `FactGuaranteeState`
- `Origin*AutomatonCoherence`

alors il faut supprimer cette dependance de la voie preuve, pas la rendre un peu plus coherente.

## Commandes utiles

Build:

```sh
opam exec -- dune build --display short
```

OBC proof-clean:

```sh
./_build/default/bin/dev/emit_obc_v2.exe tests/with_calls/ok/inputs/delay_core.kairos
```

Why brut:

```sh
./_build/default/bin/dev/emit_why_raw.exe tests/with_calls/ok/inputs/delay_core.kairos | rg "__aut_state|Aut[0-9]+|__pre_k"
```

Preuve JSON:

```sh
./_build/default/bin/dev/prove_v2_json.exe tests/with_calls/ok/inputs/delay_core.kairos 5
```

VS Code reinstall:

```sh
./scripts/vscode.sh --no-open
```

## Fichiers les plus pertinents

- [pipeline_v2_indep.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/pipeline_v2_indep.ml)
- [emit.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml)
- [why_contracts.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml)
- [why_runtime_view.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml)
- [why_env.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.ml)
- [product_kernel_ir.mli](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.mli)
- [kernel_guided_contract.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/kernel_guided_contract.ml)
- [extension.ts](/Users/fdabrowski/Repos/kairos/kairos-dev/extensions/kairos-vscode/src/extension.ts)
- [kairos_lsp.ml](/Users/fdabrowski/Repos/kairos/kairos-dev/bin/lsp/kairos_lsp.ml)

