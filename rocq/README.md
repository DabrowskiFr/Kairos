# Rocq Model (Automata-Only, Oracle-Conditional)

## Fichiers centraux

- `KairosOracle.v`
- `core/AutomataCorrectnessCore.v`
- `integration/ThreeLayerFromCore.v`
- `interfaces/ExternalValidationAssumptions.v`
- `integration/AutomataFinalCorrectness.v`

## Etat du modele monolithique

Le fichier `KairosOracle.v` contient maintenant les trois ingredients separes de la
preuve de correction automate:

1. progression explicite du produit programme × A × G,
2. noyau prouve interne qui relie une violation globale de `G` a une obligation locale
   violee,
3. fermeture finale sous hypotheses externes de validation.

Les definitions/lemmes structurants sont:

- automate programme explicite:
  `ProgramAutomaton`, `prog_select`, `step`, `cfg_at`, `ctx_at`, `run_trace`;
- automates de surete explicites:
  `SafetyAutomaton`, `SafetyAutomatonEdges`, `select_A`, `select_G`;
- produit synchrone explicite:
  `ProductState`, `ProductStep`, `product_step_wf`, `product_step_target`;
- selection du pas effectivement realise:
  `product_select_at`, `product_select_at_wf`, `product_select_at_realizes`,
  `realizable_product_step`;
- progression non bloquante:
  `product_progresses_at_each_tick`;
- noyau prouve de correction:
  `bad_local_step_if_G_violated`, `generation_coverage`;
- fermeture conditionnelle par oracle:
  `oracle_conditional_correctness`.

## Architecture de preuve factorisee

- `core/AutomataCorrectnessCore.v` reexporte le noyau prouve deja etabli dans
  `KairosOracle.v`.
- `integration/ThreeLayerFromCore.v` reconstruit la couverture
  `~AvoidG -> exists generated violated obligation` a partir des deux faits prouves
  ci-dessus, sans re-axiomatiser le coeur.
- `interfaces/ExternalValidationAssumptions.v` centralise l'unique frontiere externe:
  soundness et completeness de la validation des obligations generees.
- `integration/AutomataFinalCorrectness.v` donne le theoreme final modulaire:
  `automata_program_correctness`.

## Hypotheses externes residuelles

Hypotheses structurelles du modele:

- `prog_select_enabled`,
- `select_A_src`, `select_A_label`,
- `select_G_src`, `select_G_label`,
- `A_init_not_bad`, `G_init_not_bad`.

Hypotheses de validation externe:

- `oracle_sound_true`,
- `oracle_complete_generated`.

Le noyau "violation globale -> pas local dangereux -> obligation generee violee" est,
lui, prouve dans Rocq et non suppose.
