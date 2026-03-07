# Rocq Model (Automata-Only, Triple-Validity-Centric)

## Main Proof Path

- `MainProofPath.v`
- `KairosOracle.v`
- `core/AutomataCorrectnessCore.v`
- `integration/ThreeLayerFromCore.v`

This is the path to read first.

- `KairosOracle.v` contains the actual mathematical kernel.
- `MainProofPath.v` is the minimal entry point exposing the key proved facts.
- `core/AutomataCorrectnessCore.v` and `integration/ThreeLayerFromCore.v`
  provide lightweight derived views of the same kernel.

## Seven-Step Reading Path

To match the intended proof decomposition, the preferred structured reading is:

1. `path/Step1SemanticProduct.v`
2. `path/Step2GeneratedClauses.v`
3. `path/Step3RelationalTriples.v`
4. `path/Step4TransitionBundles.v`
5. `path/Step5TripleValidity.v`
6. `path/Step6ClauseRecovery.v`
7. `path/Step7GlobalToLocal.v`

These files are lightweight facades over `KairosOracle.v`. They do not add new
axioms or new proof content; they only expose the current kernel following the
semantic decomposition:

1. semantic product `program × A × G`;
2. extraction of generated clauses;
3. construction of relational Hoare triples;
4. later transition-level bundling refinement;
5. validity of generated triples;
6. recovery of clause validity on concrete ticks;
7. reduction from global violation to a locally falsified clause.

## Optional Refinement Layers

These files are not part of the main mathematical path and should be read only
if one wants to model external validation stacks or backend bridges:

- `interfaces/ExternalValidationAssumptions.v`
- `integration/ThreeLayerArchitecture.v`
- `integration/AutomataFinalCorrectness.v`
- `obligations/TransitionTriplesBridge.v`
- `obligations/HoareExternalBridge.v`
- `obligations/ImplementationValidatorBridge.v`

When reading these layers, prefer the vocabulary:

- `VALIDATION_SIG`
- `VALIDATION_SEM_SIG`
- `VALIDATION_ASSUMPTIONS`
- files:
  - `obligations/ValidationSig.v`
  - `obligations/ValidationSemSig.v`
  - `interfaces/ValidationAssumptions.v`

The older `ORACLE_*` names remain only as compatibility aliases.

## Etat du modele monolithique

Le fichier `KairosOracle.v` contient maintenant les trois ingredients separes de la
preuve de correction automate:

1. progression explicite du produit programme × A × G,
2. noyau prouve interne qui relie une violation globale de `G` a une obligation locale
   violee,
3. fermeture finale sous hypothese de validite des triples generes.

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
- fermeture conditionnelle par validite de triples:
  `triple_valid_conditional_correctness`.

## Vues derivees minimales

- `core/AutomataCorrectnessCore.v` reexporte le noyau prouve deja etabli dans
  `KairosOracle.v`.
- `integration/ThreeLayerFromCore.v` reconstruit la couverture
  `~AvoidG -> exists generated violated obligation` a partir des deux faits prouves
  ci-dessus, sans re-axiomatiser le coeur.
- `MainProofPath.v` donne le point d'entree le plus lisible pour ces faits.

## Hypotheses centrales du noyau

Hypotheses structurelles du modele:

- `prog_select_enabled`,
- `select_A_src`, `select_A_label`,
- `select_G_src`, `select_G_label`,
- `A_init_not_bad`, `G_init_not_bad`.

Hypothese de preuve:

- `GeneratedTripleValid`.

Le noyau "violation globale -> pas local dangereux -> clause/triple genere viole"
est, lui, prouve dans Rocq et non suppose.

## Raffinements optionnels

Si l'on veut modeliser un validateur externe, des bundles Why3 ou un checker,
on passe alors par les bridges optionnels listes plus haut. Ils ne doivent plus
etre confondus avec le chemin principal de lecture du noyau.
