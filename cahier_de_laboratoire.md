# Cahier de laboratoire

## 2026-03-06

### Sujet
Instanciation Coq concrete du cas `delay_int.kairos` dans `rocq/DelayIntExample.v`.

### Tentative 1 (echec partiel)
- Objectif: prouver en plus `avoids_bad_G` via un automate de garantie encode en arêtes.
- Resultat: echec de preuve robuste sur l'encodage `SafetyAutomatonEdges` (inference de types dependants `q A`) et re-ecritures fragiles dans la preuve de transition.
- Cause:
  - forte verbosite des projections dependantes,
  - mismatchs de re-ecriture sur definitions alias/expansees (`out_at`, `cfg_at`).

### Tentative 2 (succes)
- Objectif: conserver une preuve de correction de bout en bout directement sur la semantique du programme.
- Resultat: succes.
- Preuves obtenues:
  - `cfg_at_succ`: a partir du tick 1, la config vaut toujours `(SRun, u k)`,
  - `out_at_0`: la premiere sortie vaut `0`,
  - `out_at_succ`: pour `k>=0`, `out_at (S k) = u k`,
  - `delay_end_to_end`: combinaison de la loi de flux et de l'invariant memoire d'execution.

### Decisions
- Garder cette version comme base stable et compilable.
- Reintroduire la preuve automate G en arêtes dans un second temps, avec un encodage auxiliaire des types dependants pour eviter les blocages d'inference.

### Mise a jour (automates + produit) - succes
- Action:
  - extension de `rocq/DelayIntExample.v` avec une section `AutomataProductFacts`.
  - ajout d'automates concrets:
    - `A_aut` (AOk/ABad) avec arêtes dependantes (`sigT`),
    - `G_aut` (GInit/GRun/GBad) avec arêtes dependantes (`sigT`) et delta de delay.
  - preuves:
    - `aut_state_A_all_ok`,
    - `aut_state_G_succ`,
    - `avoids_bad_A_delay`,
    - `avoids_bad_G_delay`,
    - `product_state_0`,
    - `product_state_succ`.
- Echecs rencontres:
  - collisions de noms entre sections,
  - re-ecritures fragiles via alias (`cfg_at`, `out_at`),
  - typage dependant des projections `q A` dans les enregistrements produit/aretes.
- Correctifs:
  - namespace de lemmes distinct (`*_rf` vs section automates),
  - re-ecritures via hypotheses explicites (`pose proof ... as Hcfg`),
  - annotations explicites de type dans les etats produit,
  - pattern `remember` pour stabiliser l'induction sur la trace.
- Validation:
  - `coqc rocq/DelayIntExample.v` OK.

### Mise a jour (shift abstrait en Coq) - succes
- Demande: ne pas exposer `pre_k` en Coq, mais formaliser un operateur abstrait de decalage avec correction.
- Changement:
  - ajout dans `rocq/KairosOracle.v` de:
    - `FO`, `eval_fo`, `shift_fo`,
    - hypothese `shift_fo_correct`,
    - lemme derive `shift_fo_correct_one_step`,
    - theoreme de transfert `shifted_formula_transfers_to_successor`.
- Sens formalise:
  - evaluation de `shift_fo 1 phi` au tick `k`
  - equivalente a l'evaluation de `phi` au tick `k+1`.
- Validation:
  - `coqc rocq/KairosOracle.v` OK.
  - `coqc rocq/DelayIntExample.v` OK (pas de regression).

### Mise a jour (shift conditionne par admissibilite d'entree) - succes
- Demande: remplacer la loi de shift inconditionnelle par une loi explicite sous hypothese d'entree admissible.
- Changement dans `rocq/KairosOracle.v`:
  - ajout de `InputOk u k := aut_state_at_A u k <> bad_A`,
  - lemme pont `avoids_bad_A_implies_InputOk`,
  - remplacement de `shift_fo_correct` par `shift_fo_correct_if_input_ok`,
  - adaptation des lemmes derives (`shift_fo_correct_one_step`, `shifted_formula_transfers_to_successor`).
- Effet:
  - le raisonnement de decalage n'est plus global,
  - il est conditionne par la non-violation de l'hypothese d'entree.
- Validation:
  - `coqc rocq/KairosOracle.v` OK,
  - `coqc rocq/DelayIntExample.v` OK.

### Mise a jour (architecture modulaire par modules/foncteurs) - succes partiel
- Demande: integrer la modularite Rocq (Module Type + foncteur) dans le projet, au-dela du simple squelette.
- Changements:
  - `rocq/KairosModularArchitecture.v`:
    - ajout de `INPUT_OK_LINK_SIG` pour relier explicitement `InputOk` issu de l'automate A et `InputOk` de la logique FO,
    - affaiblissement de `HISTORY_LOGIC_SIG` pour une correction du shift sur un `InputOk` fixe (au lieu de quantifier sur tout predicat),
    - adaptation du foncteur `MakeCorrectness` pour utiliser ce lien.
  - `rocq/KairosModularIntegration.v` (nouveau):
    - definition d'un `Module Type KAIROS_ORACLE_INSTANCE_SIG`,
    - foncteur `KairosModularBridge` qui instancie concretement le foncteur de correction sur les objets de `KairosOracleModel`,
    - theoreme pont `modular_shifted_formula_transfers_to_successor_under_A`.
- Difficultes rencontrees:
  - incompatibilites d'arguments implicites dans les appels de lemmes,
  - contrainte Rocq: modules interdits dans une `Section`,
  - obligations de champs explicites dans les implementations de signatures (`stream`, `aut_state_at`, `avoids_bad`, `Obligation`).
- Correctifs:
  - passage a un bridge fonctoriel (sans section),
  - ajout d'un lemme de correspondance `A_aut_state_at_eq` pour reconnecter `avoids_bad_A` concret et `C.AvoidA`.
- Validation:
  - `coqc rocq/KairosModularArchitecture.v` OK,
  - `coqc rocq/KairosModularIntegration.v` OK.
- Limite actuelle:
  - l'engine d'obligations dans le bridge est volontairement minimal (`unit/True`) pour isoler le raccord shift/admissibilite; l'integration complete oracle/obligations est encore a faire.

### Mise a jour (modele de refactor applicatif) - succes
- Demande: preparer la formalisation pour servir de modele de refonte de l'application.
- Livrables ajoutes:
  - `rocq/KairosRefactorBlueprint.v`:
    - signatures modulaires cible (`CORE_STEP_SIG`, `MONITOR_SIG`, `INPUT_ADMISSIBILITY_SIG`, `FO_LOGIC_SIG`, `SHIFT_SPEC_SIG`, `OBLIGATION_GEN_SIG`, `ORACLE_SIG`, `REFINEMENT_SIG`),
    - noyau de preuve `MakeShiftKernel` pour le transfert de formule decalee sous `AvoidA`.
  - `rocq/RefactorArchitecturePlan.md`:
    - arborescence cible,
    - mapping avec les fichiers existants,
    - checkpoints de migration et criteres de pret.
- Incident technique:
  - collision/ambiguite d'arguments implicites dans `avoid_implies_input_ok`.
- Correctif:
  - appel explicite `@Ain.avoid_implies_input_ok u k HA`.
- Validation:
  - `coqc rocq/KairosRefactorBlueprint.v` OK.

### Mise a jour (migration modulaire structuree + compilation globale) - succes
- Demande: executer l'ensemble des etapes (arborescence cible, raccord obligations/oracle, raffinement, theoremes modulaires).
- Travaux realises:
  - creation de l'arborescence Rocq cible:
    - `rocq/core/*`,
    - `rocq/monitor/*`,
    - `rocq/logic/*`,
    - `rocq/obligations/*`,
    - `rocq/refinement/*`,
    - `rocq/kernels/*`,
    - `rocq/instances/*`,
    - `rocq/integration/*`.
  - remplacement du stub d'obligations dans `rocq/KairosModularIntegration.v`:
    - `EConcrete.origin := KairosOracleModel.origin`,
    - `EConcrete.GeneratedBy` branche sur `KairosOracleModel.GeneratedBy` (existentiel sur la transition).
  - ajout d'un kernel de surete modulaire avec contrat explicite:
    - `ObligationValid_pointwise` requis pour relier validite oracle et satisfaction locale de l'obligation.
  - ajout des signatures de raffinement et du raffinement de shift abstrait.
- Echecs rencontres et causes:
  - resolution loadpath Coq dans les sous-dossiers (`core.*`, `monitor.*`): besoin de `-Q rocq ''`.
  - erreurs recurrentes d'arguments implicites sur les lemmes modulaires.
  - trou de contrat dans le kernel surete (`ObligationValid` trop abstrait sans lien pointwise).
- Correctifs:
  - compilation systematique avec `coqc -Q /Users/fredericdabrowski/Repos/kairos/rocq '' ...`,
  - appels explicites (`@...`) sur les hypotheses modulees,
  - ajout du contrat `ObligationValid_pointwise` dans `MakeSafetyKernel`.
- Validation:
  - compilation globale des nouveaux modules et ponts: OK.

### Mise a jour (architecture 3 couches programme/noyau/validation) - succes
- Demande: structurer explicitement la formalisation en trois couches avec programme abstrait et validation abstraite des obligations.
- Changement:
  - ajout de `rocq/integration/ThreeLayerArchitecture.v` avec:
    - `PROGRAM_LAYER_SIG` (semantique reactive abstraite + `AvoidA`/`AvoidG`),
    - `KAIROS_CORE_LAYER_SIG` (generation d'obligations + couverture locale),
    - `VALIDATION_LAYER_SIG` (validation abstraite + lien pointwise de validite),
    - foncteur `MakeThreeLayerCorrectness` et theoreme global:
      `oracle_conditional_correctness_three_layers`.
- Point cle:
  - la preuve globale ne depend que des contrats des 3 couches (aucune hypothese sur un langage Kairos concret).
- Validation:
  - `coqc -Q /Users/fredericdabrowski/Repos/kairos/rocq '' integration/ThreeLayerArchitecture.v` OK.

### Mise a jour (fermeture des liens critiques pour le refactor) - succes
- Objectif: traiter les points critiques identifies en review (contrat de validation, lois reactives, unification interfaces, instance concrete).
- Changements:
  - nouveau contrat semantique de validation:
    - ajout de `rocq/obligations/OracleSemSig.v` avec `obligation_valid_pointwise`,
    - `rocq/kernels/SafetyKernel.v` et `rocq/integration/EndToEndTheorem.v` bascules sur `ORACLE_SEM_SIG`.
  - lois reactives explicites:
    - ajout de `rocq/core/CoreReactiveLaws.v`,
    - `rocq/integration/ThreeLayerArchitecture.v` exige des lois de coherence `ctx/cfg/trace`.
  - unification blueprint:
    - `rocq/KairosRefactorBlueprint.v` devient un fichier d'aliases vers les modules canoniques (suppression des definitions dupliquees),
    - suppression de `ORACLE_SIG` redondant dans `rocq/KairosModularArchitecture.v`.
  - instance concrete 3 couches:
    - `rocq/instances/DelayIntInstance.v` fournit une instance complete `Program/Core/Solver` et derive:
      - `delay_int_three_layer_correctness`,
      - `delay_int_three_layer_unconditional`.
- Validation:
  - compilation OK de tous les fichiers modifies via `coqc -Q /Users/fredericdabrowski/Repos/kairos/rocq '' ...`.

### Mise a jour (pont correction -> specification LTL abstraite) - succes
- Demande: introduire une notion abstraite de formule LTL et relier la correction programme a une specification LTL.
- Ajouts:
  - `rocq/logic/LTLPredicate.v`:
    - formule LTL abstraite comme predicat sur flux (`Formula := stream Obs -> Prop`),
    - semantique `sat`.
  - `rocq/monitor/MonitorLTLLink.v`:
    - contrat `monitor_implements_phi : avoids_bad <-> sat phi`.
  - `rocq/integration/ProgramLTLSpecBridge.v`:
    - contrat de spec programme `avoidG_characterizes_phiG`,
    - foncteur `MakeProgramLTLCorrectness`,
    - theoreme `program_satisfies_ltl_under_A`.
  - `rocq/KairosRefactorBlueprint.v`:
    - aliases vers ces nouveaux modules.
- Validation:
  - compilation OK des nouveaux modules et du blueprint.

### Mise a jour (extensions abstraites pour raccord concret sans surcharge) - succes
- Demande: ajouter des abstractions pour connecter la formalisation a des elements concrets, sans concretiser le langage ni l'outil de validation.
- Ajouts implementes:
  - compilation de contrats:
    - `rocq/contracts/ContractCompilerSig.v`
    - interface `CONTRACT_COMPILER_SIG` avec lois de correction `compile_A_sound_complete` et `compile_G_sound_complete`.
  - (retire ensuite du coeur) ancienne variante de validation graduee.
  - non-vacuite:
    - `rocq/integration/AdmissibilityNonVacuity.v` avec temoin admissible,
    - theoreme d'existence d'une trace satisfaisant la garantie.
  - blueprint:
    - `rocq/KairosRefactorBlueprint.v` enrichi avec aliases/foncteurs de ces nouvelles couches.
- Validation:
  - compilation OK des nouveaux modules du coeur (`contracts`, `AdmissibilityNonVacuity`, blueprint).

### Mise a jour (separation explicite des obligations par role + ordre) - succes
- Demande: separer clairement les obligations necessaires et assistantes, en distinguant support automate vs support utilisateur, avec un ordre logique.
- Ajouts:
  - `rocq/obligations/ObligationTaxonomySig.v`:
    - roles:
      - `ObjectiveNoBad`,
      - `SupportAutomaton`,
      - `SupportUserInvariant`,
    - partition + disjonction des classes.
  - `rocq/obligations/ObligationStratifiedSig.v`:
    - phases ordonnees:
      - `PhaseObjective`,
      - `PhaseSupportAutomaton`,
      - `PhaseSupportUserInvariant`,
    - theoremes d'ordre (`Objective` avant `SupportAutomaton`, puis `SupportUserInvariant`).
  - `rocq/KairosRefactorBlueprint.v`:
    - aliases des nouvelles interfaces taxonomie/stratification.
- Validation:
  - `coqc` OK sur `ObligationTaxonomySig.v`, `ObligationStratifiedSig.v`, `KairosRefactorBlueprint.v`.

### Mise a jour (couverture explicite des obligations objectif) - succes
- Demande: formaliser le renforcement \"si G est violee, on extrait une obligation objectif\".
- Ajout:
  - `rocq/kernels/ObjectiveSafetyKernel.v`:

### Mise a jour (alignement v2 verification sur taxonomie Rocq) - succes
- Demande:
  - pousser la v2 jusqu'a une procedure de verification explicitement alignee sur la formalisation Rocq,
  - conserver la generation effective d'obligations inspiree de la v1 quand elle correspond a ce qui est formalise.
- Changements implementation:
  - ajout de `lib/pipeline/obligation_taxonomy.ml(.mli)`:
    - familles explicites d'obligations cote implementation:
      - `transition_requires`,
      - `transition_ensures`,
      - `coherency_requires`,
      - `coherency_ensures_shifted`,
      - `initial_coherency_goal`,
      - `no_bad_requires`,
      - `no_bad_ensures`,
      - `monitor_compatibility_requires`,
      - `state_aware_assumption_requires`.
    - classification par provenance (`UserContract`, `Coherency`, `Instrumentation`, `Compatibility`, `AssumeAutomaton`).
  - integration dans `lib/pipeline/pipeline_v2_indep.ml`:
    - calcul de la taxonomie sur l'OBC augmente reellement utilise pour Why3,
    - enrichissement de `obligations_map_text` avec un bloc `-- OBC obligation taxonomy --`,
    - enrichissement de `stage_meta` avec une section `obligations_taxonomy`.
- Impact:
  - la v2 expose maintenant explicitement les familles d'obligations effectivement verifiees,
  - on se rapproche du decoupage Rocq (objectif/support automate/support utilisateur) tout en gardant la chaine de generation v1 existante.
- Validation:
  - compilation `dune build` du depot Kairos: OK.

### Mise a jour (suppression complete du chemin v1) - succes
- Demande:
  - eliminer completement la v1 dans la branche de refactoring,
  - conserver `develop` uniquement comme reference de comparaison.
- Changements:
  - `engine_service` passe en v2-only (`type engine = V2`), suppression des branches `V1` et `Auto`.
  - CLI `kairos`:
    - suppression du fallback `Runner`/v1,
    - suppression de l'option `--engine` (v2 unique),
    - message explicite quand des options non supportees v2 sont demandees.
  - IDE/LSP:
    - normalisation engine forcee a `v2`,
    - suppression des options UI `v1|auto` (label + sanitization).
  - `lib_v2`:
    - suppression des fichiers `v1_external_bridge.ml/.mli`,
    - mise a jour de `lib_v2/README.md` pour documenter le bridge natif v2.
- Validation:
  - build `dune build` du depot Kairos: OK.
  - execution smoke v2 (`dump-obligations-map`, `dump-why`): OK.

### Mise a jour (suppression du repertoire `lib/` au profit de `lib_v2`) - succes
- Demande:
  - finaliser la bascule pour ne plus garder de repertoire `lib` de premier niveau.
- Changement structurel:
  - deplacement complet de `lib/` vers `lib_v2/runtime/`,
  - mise a jour de la racine `dune`:
    - suppression de `lib` dans `(dirs ...)`,
    - conservation de `lib_v2` comme racine unique des bibliotheques applicatives.
- Validation:
  - `dune build` OK,
  - `dune exec -- kairos --dump-obligations-map - tests/ok/inputs/delay_int.kairos` OK,
  - `dune exec -- kairos_v2 --dump-why - tests/ok/inputs/toggle.kairos` OK.

### Mise a jour (purge finale des points d'entree legacy) - succes
- Demande:
  - eliminer les derniers points d'entree legacy encore presents dans `pipeline`.
- Actions:
  - suppression du module `runner` du runtime (`runner.ml/.mli` supprimes, retrait du `dune`).
  - neutralisation explicite des anciennes entrees `Pipeline`:
    - `instrumentation_pass`,
    - `obc_pass`,
    - `why_pass`,
    - `obligations_pass`,
    - `run`,
    - `run_with_callbacks`,
    qui renvoient toutes une erreur "Legacy ... removed".
- Validation:
  - `dune build` OK,
  - commandes smoke v2 OK (`kairos`, `kairos_v2`).
    - interface `LOCAL_OBJECTIVE_COVERAGE_SIG` avec
      `objective_coverage_if_not_avoidG`,
    - foncteur `MakeObjectiveSafetyKernel`,
    - theoreme `oracle_conditional_correctness_from_objectives`.
- Effet:
  - la correction peut maintenant etre prouvee a partir des seules obligations
    `ObjectiveNoBad` (les supports ne sont plus necessaires dans ce chemin).
- Validation:
  - `coqc` OK sur `ObjectiveSafetyKernel.v` et `KairosRefactorBlueprint.v`.

### Mise a jour (support non bloquant) - succes
- Demande: formaliser que les obligations de support n'affectent pas le coeur de correction.
- Ajout:
  - `rocq/kernels/SupportNonBlockingKernel.v` avec le theoreme:
    - `correction_preserved_if_oracles_agree_on_objectives`.
- Lecture:
  - si deux oracles peuvent differer, mais qu'ils sont alignes sur les obligations
    `ObjectiveNoBad`, alors la correction (A => G) est preservee.
- Validation:
  - compilation OK de `SupportNonBlockingKernel.v` et du blueprint.

### Mise a jour (suppression du vocabulaire solveur du coeur) - succes
- Demande: ne plus parler de solveur, rester au niveau abstrait de validite des obligations.
- Changements:
  - renommage de la couche `SOLVER_LAYER_SIG` en `VALIDATION_LAYER_SIG` dans `ThreeLayerArchitecture`.
  - propagation du renommage dans:
    - `ProgramLTLSpecBridge`,
    - `AdmissibilityNonVacuity`,
    - `DelayIntInstance` (`Module Validation`).
  - retrait du chemin principal des modules de validation graduee et suppression des fichiers:
    - `rocq/obligations/OracleGradedSig.v`,
    - `rocq/kernels/GradedSafetyKernel.v`.
  - nettoyage du blueprint et de la documentation.
- Validation:
  - compilation OK de la chaine principale apres renommage.

### Mise a jour (pont implementation -> validite des obligations) - succes
- Demande: ajouter un contrat explicite pour relier l'implementation a la validite abstraite des obligations.
- Ajout:
  - `rocq/obligations/ImplementationValidatorBridge.v`:
    - `IMPLEMENTATION_VALIDATOR_SIG` (validator bool + correction semantique),
    - foncteur `MakeOracleSemFromValidator` vers `ORACLE_SEM_SIG`.
- Point cle:
  - le coeur reste abstrait (validite des obligations),
  - le lien outillage concret est factorise dans un bridge dedie.
- Validation:
  - compilation OK de `ImplementationValidatorBridge.v` et du blueprint.

### Mise a jour (pont Hoare + outil externe) - succes
- Demande: remplacer le schema \"outil verifie directement des obligations\" par
  \"obligations -> triplets/taches Hoare -> verification externe\".
- Ajout:
  - `rocq/obligations/HoareExternalBridge.v` avec:
    - `HOARE_TASK_GEN_SIG` (encodage d'obligation en triplet Hoare),
    - `EXTERNAL_VC_TOOL_SIG` (outil externe de verification),
    - `MakeOracleSemFromHoareTool` (adaptation vers `ORACLE_SEM_SIG`).
- Hypothese externe explicite:
  - `check_sound`: si l'outil dit oui sur la tache Hoare, alors la tache est valide.
- Validation:
  - compilation OK de `HoareExternalBridge.v` et du blueprint.

### Mise a jour (2026-03-06, document mathematique rocq) - succes
- Demande: mettre a jour `spec/rocq_oracle_model.tex` pour expliquer toutes les etapes,
  avec exemples systematiques `delay_int` et `toggle`, et representations graphiques des automates.
- Changements:
  - ajout d'une section complete: `Lecture par etapes avec deux exemples fil rouge`.
  - 8 etapes explicites (programme, semantique de flux, automates A/G, produit,
    obligations locales, taxonomie, pont outil externe, theoreme global).
  - ajout de schemas TikZ comparatifs (`delay_int` vs `toggle`) pour les automates
    de programme et les automates de garantie.
- Validation:
  - recompilation PDF OK via `latexmk -pdf`.
  - sortie: `spec/rocq_oracle_model.pdf` (10 pages).

### Mise a jour (2026-03-06, lancement du refactoring implementation v2) - succes partiel
- Demande: demarrer un nouveau projet dans un nouveau repertoire, base sur l'architecture Rocq,
  avec executable dedie et ponts vers composants externes existants.
- Realisation:
  - creation de `lib_v2/` avec sous-dossiers:
    - `interfaces/` (frontieres abstraites),
    - `pipeline/` (entree v2),
    - `adapters/` (pont v1 externe).
  - ajout d'un nouveau binaire `kairos_v2` dans `bin/cli/dune`.
  - ajout de `lib_v2/README.md` documentant la structure.
- Validation:
  - echec de compilation globale, cause externe a `lib_v2`:
    - erreurs preexistantes dans `lib/backend/why/why_prove.ml` et `lib/backend/emit.ml`.
  - conclusion: integration structurelle faite, validation executable bloquee tant que le tronc courant ne compile pas.

### Mise a jour (2026-03-07, clarification de la correction automate Rocq + documentation) - succes
- Demande:
  - reprendre le chantier de formalisation Rocq et la documentation PDF pour clarifier
    la correction vis-a-vis des automates de surete, avec separation nette entre:
    - non atteinte de `bad_G`,
    - progression explicite du produit,
    - hypotheses externes.
- Constat initial:
  - la branche courante est bien `codex/refactoring-architecture-rocq`;
  - les nouveaux fichiers de decomposition de preuve sont presents:
    - `rocq/core/AutomataCorrectnessCore.v`,
    - `rocq/integration/ThreeLayerFromCore.v`,
    - `rocq/interfaces/ExternalValidationAssumptions.v`,
    - `rocq/integration/AutomataFinalCorrectness.v`,
    - `rocq/PROOF_STATUS.md`;
  - contrairement au contexte annonce, `dune build` echoue initialement sur du code OCaml
    hors Rocq:
    - `lib_v2/runtime/backend/emit.ml`,
    - `lib_v2/runtime/backend/why/why_prove.ml`.
- Verification Rocq:
  - compilation OK avec `opam exec --switch=default -- coqc -Q rocq ''` sur:
    - `rocq/KairosOracle.v`,
    - `rocq/core/AutomataCorrectnessCore.v`,
    - `rocq/integration/ThreeLayerFromCore.v`,
    - `rocq/interfaces/ExternalValidationAssumptions.v`,
    - `rocq/integration/AutomataFinalCorrectness.v`.
- Lecture technique retenue:
  - `KairosOracle.v` contient bien maintenant un chemin de preuve explicite:
    - `product_select_at`,
    - `product_select_at_wf`,
    - `product_select_at_realizes`,
    - `realizable_product_step`,
    - `product_progresses_at_each_tick`,
    - `bad_local_step_if_G_violated`,
    - `generation_coverage`,
    - `oracle_conditional_correctness`.
  - la progression du produit est donc prouvee, et non simplement supposee.
  - le theoreme final modulaire ne depend plus que de la validation externe des
    obligations generees.
- Mise a jour documentaire:
  - `rocq/README.md`:
    - reecriture pour faire apparaitre la decomposition
      "progression du produit / noyau prouve / hypotheses externes / theoreme final".
  - `rocq/PROOF_STATUS.md`:
    - ajout explicite du statut de `product_progresses_at_each_tick`,
    - ajout de `ThreeLayerFromCore.v` comme couche de reconstruction depuis le noyau prouve,
    - clarification: le non-blocage est prouve en Rocq.
  - `rocq/RefactorArchitecturePlan.md`:
    - mise a jour de l'objectif courant, de la methodologie et des prochaines etapes
      pour ce chantier.
  - `spec/rocq_oracle_model.tex`:
    - alignement de la section de tracabilite avec les nouveaux modules,
    - ajout d'une remarque explicite sur la progression du produit comme fait prouve.
- Pourquoi certaines tentatives etaient insuffisantes avant cette mise a jour:
  - se contenter du theoreme final ou du seul noyau monolithique ne rendait pas visible
    la frontiere exacte entre faits internes prouves et hypotheses externes.
  - documenter uniquement `bad_local_step_if_G_violated` et `generation_coverage`
    laissait implicite la question du non-blocage du produit.
- Validation intermediaire:
  - `coqc` OK sur toute la chaine Rocq ciblee.
  - `dune build` KO a ce stade, echec hors perimetre de cette sous-passe.

### Mise a jour (2026-03-07, compatibilite Why3 1.8.2 et validation globale en switch 5.4.1+options) - succes
- Demande:
  - clarifier l'environnement opam actif et revalider la compilation complete du
    projet OCaml et du projet Rocq avec un unique switch.
- Methodologie retenue:
  - abandon des verifications faites dans `default` et `5.3.0+options`;
  - adoption du switch unique `5.4.1+options` pour toutes les commandes;
  - correction minimale des incompatibilites API Why3 avant recompilation globale.
- Corrections appliquees:
  - `lib_v2/runtime/backend/why/why_prove.ml`:
    - adaptation a l'API Why3 recente:
      `Pmodule.mod_theory m` -> `m.Pmodule.mod_theory`.
  - `lib_v2/runtime/backend/emit.ml`:
    - adaptation du constructeur `Ptree.Modules` qui attend maintenant des couples
      `(ident, decl list)` plutot que des triples avec qualid optionnel.
- Pourquoi l'ancien code echouait:
  - il correspondait a une API Why3 plus ancienne;
  - dans le switch actif, la bibliotheque exposee est compatible avec l'acces
    en champ `m.Pmodule.mod_theory` et avec `Ptree.Modules [ (id, decls) ]`.
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build`:
    - succes.
  - compilation Rocq globale:
    - generation makefile:
      `opam exec --switch=5.4.1+options -- rocq makefile -Q rocq "" ...`;
    - compilation:
      `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2`;
    - succes jusqu'aux theoremes finaux (`AutomataFinalCorrectness.v`,
      `KairosRefactorBlueprint.v`).
- Conclusion:
  - l'environnement de travail courant est maintenant stabilise autour de
    `5.4.1+options`;
  - le projet OCaml et le projet Rocq recompilent tous deux dans cet environnement;
  - les corrections documentaires et de preuve peuvent desormais etre discutees sans
    ambiguite sur l'etat du build.

### Mise a jour (2026-03-07, section technique sur le produit explicite vs implementation actuelle) - succes
- Demande:
  - ajouter au document mathematique une section qui explique:
    - que l'implementation actuelle ne materialise pas un automate produit explicite,
    - pourquoi un IR produit `programme x A x G` serait architecturalement meilleur,
    - et en quel sens il reste equivalent au pipeline courant.
- Analyse du code courant:
  - le pipeline construit separement les automates de garantie et d'hypothese;
  - il injecte un seul etat runtime `__aut_state` pour le moniteur principal;
  - les calculs de type produit existent deja, mais localement et de maniere
    fragmentee:
    - reachability `programme x G`,
    - compatibilite `G x A`,
    - generation de `requires` et d'obligations.
  - il n'y a donc pas aujourd'hui d'IR central explicite pour
    `programme x A x G`.
- Mise a jour documentaire:
  - ajout dans `spec/rocq_oracle_model.tex` d'une section technique explicitant:
    - la difference entre preuve a produit explicite et implementation instrumentee;
    - les benefices architecturaux d'un produit explicite
      (source semantique unique, alignement avec Rocq, tracabilite des obligations);
    - l'argument d'equivalence semantique attendu
      (memes triples atteignables, meme critere `bad_G`, memes obligations modulo compilation).
- Validation:
  - recompilation PDF apres modification de la section technique.

### Mise a jour (2026-03-07, implantation du noyau produit `programme x A x G` dans le middle-end) - succes
- Demande:
  - passer du plan d'architecture a une implementation concrete;
  - unifier le traitement de `A x G` et `programme x A x G` autour d'un noyau produit explicite;
  - expliquer les principes et l'equivalence dans le document PDF.
- Implantation realisee:
  - ajout d'un sous-ensemble de modules `product/*` dans
    `lib_v2/runtime/middle_end/`:
    - `product_types.{ml,mli}`:
      etats produit, pas produits, classes de pas, pruning;
    - `product_build.{ml,mli}`:
      construction/exploration du graphe atteignable
      `programme x A x G` a partir:
      - des transitions programme,
      - de l'automate d'hypothese,
      - de l'automate de garantie;
    - `product_debug.{ml,mli}`:
      rendu texte/DOT du produit, des obligations locales et des raisons de pruning.
  - integration de ce noyau dans `instrumentation.ml`:
    - les metadonnees `product_lines`, `prune_lines`, `obligations_lines`,
      `product_dot`, `assume_automaton_*`, `guarantee_automaton_*`
      sont maintenant peuplees depuis le produit explicite.
- Choix d'architecture retenu:
  - le produit explicite sert de noyau semantique partage;
  - l'instrumentation executable existante (`__aut_state`, backend OBC/Why3)
    est conservee comme couche de compilation/backend;
  - on obtient donc une architecture intermediaire:
    - IR produit explicite pour la semantique et les diagnostics,
    - backend instrumente pour l'execution et l'emission externe.
- Pourquoi cette etape est utile meme si toute la logique n'a pas encore migre:
  - elle elimine le "produit implicite" eparpille dans plusieurs passes;
  - elle donne une representation canonique des triples atteignables;
  - elle prepare la migration future des obligations et de la compatibilite
    vers le produit explicite, sans casser le pipeline courant.
- Documentation:
  - mise a jour de `spec/rocq_oracle_model.tex` pour decrire:
    - le noyau produit explicite maintenant present dans le code,
    - le caractere on-the-fly de l'exploration,
    - la projection vers l'instrumentation `__aut_state`,
    - l'argument d'equivalence semantique avec l'ancien pipeline.
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build`: succes.
  - recompilation PDF `spec/rocq_oracle_model.tex`: succes.

### Mise a jour (2026-03-07, migration de la generation de contrats vers le produit explicite) - succes
- Demande:
  - poursuivre la migration pour que les hypotheses et obligations ne soient plus
    reconstruites via une logique separee de type `G x A` / `programme x G`,
    mais derivees du produit explicite `programme x A x G`.
- Implantation realisee:
  - ajout de `product_contracts.ml` dans la couche `product/*`;
  - les invariants de compatibilite par etat programme sont maintenant projetes
    depuis les etats atteignables du produit explicite;
  - les preconditions reliees aux hypotheses sont derivees des pas du produit,
    puis projetees sur l'etat runtime `__aut_state`;
  - les obligations locales bloquant les pas `bad_G` sont derivees des pas du
    produit, puis ajoutees comme `ensures` projetes.
- Changement d'architecture:
  - `Gen_hyp` / `Gen_obl` ne sont plus le centre logique de la generation;
  - l'orchestration dans `instrumentation.ml` passe maintenant directement par:
    - le produit explicite,
    - ses projections de compatibilite,
    - ses projections d'obligations.
- Interpretation:
  - l'implementation reste encore compilee vers un backend instrumente;
  - mais la source de verite pour les contrats generes est desormais le produit
    explicite plutot que des calculs locaux separes.
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build`: succes.

### Mise a jour (2026-03-07, nettoyage du code redondant apres migration produit) - succes
- Demande:
  - retirer le code mort ou redondant issu de l'ancien raisonnement fragmente.
- Nettoyage realise:
  - suppression des anciens modules `gen_hyp.ml` et `gen_obl.ml`;
  - retrait de leur enregistrement dans `lib_v2/runtime/dune`;
  - suppression dans `abstract_model.{ml,mli}` des anciens types auxiliaires de
    produit qui n'etaient plus utilises (`product_triple`, `local_combo`, etc.);
  - suppression dans `instrumentation.ml` des anciens calculateurs redondants:
    - compatibilite `programme x G`,
    - propagation `G x A`,
    - helpers logiques associes.
- Resultat:
  - la couche `product/*` devient la seule source de verite pour:
    - l'exploration du produit,
    - les raisons de pruning,
    - la projection des compatibilites,
    - la projection des obligations locales.
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build`: succes.

### Mise a jour (2026-03-07, clarification du PDF sur l'intuition du produit) - succes
- Demande:
  - mieux expliquer dans le document mathematique l'intuition du produit
    `programme x A x G`, le role d'un tick `k`, la signification de `i(k)` et
    `o(k)`, et supprimer l'ambiguite autour de l'ancienne notation `g_run`.
- Modifications:
  - ajout, dans `spec/rocq_oracle_model.tex`, d'une explication operationnelle
    tick par tick:
    - lecture de l'entree courante `i(k)`,
    - calcul du pas programme,
    - production de la sortie `o(k)`,
    - avancement synchrone de `A` et `G`;
  - explicitation du fait qu'un tick realise un unique pas produit
    `rps(u,k) -> rps(u,k+1)` et non trois evolutions separees;
  - remplacement d'une ancienne occurrence d'etat de garantie ecrit
    `g_run(u_0)` par un etat fini nomme (`Mon_1`) pour rester coherent avec
    l'exemple `delay_int`.
- Pourquoi:
  - l'ancienne presentation laissait croire que `G` embarquait des etats
    parametres par des valeurs d'execution, alors que l'historique est porte
    par la memoire programme ou le contexte d'evaluation.
- Validation:
  - recompilation PDF `spec/rocq_oracle_model.tex`: succes.

### Mise a jour (2026-03-07, reecriture de la section sur les obligations locales) - succes
- Demande:
  - rendre comprehensible la section `Obligations locales par transition`, qui
    etait trop compacte et ne definissait pas clairement ce qui est genere, ce
    que signifie `match`, ni comment lire les exemples avec `k` et `k+1`.
- Modifications:
  - reecriture de l'etape 5 pour expliquer l'intuition: une obligation locale
    interdit la realisation d'un pas produit dangereux au tick courant;
  - extension de la section formelle `Obligations locales et oracle`:
    - contexte local explicite avec etats programme et automates,
    - definition complete de `match(c,p)`,
    - definition formelle de `obl_p(c) := not match(c,p)`,
    - explication du sous-ensemble de pas generateurs (ceux qui vont vers
      `bad_G` sans passer par `bad_A`);
  - ajout d'exemples developpes pour `delay_int` et `toggle`, avec:
    - les transitions programme concernees,
    - les aretes automates concernees,
    - le matching concret,
    - l'obligation generee,
    - la forme simplifiee/projetee cote backend.
- Pourquoi:
  - la version precedente donnait la forme abstraite `obl_p := neg match`
    sans permettre au lecteur de reconstruire ce que cela signifiait pour un
    tick concret ou pour les exemples graphiques du document.
- Validation:
  - recompilation PDF `spec/rocq_oracle_model.tex`: succes.

### Mise a jour (2026-03-07, restructuration pedagogique du document PDF) - succes
- Demande:
  - ameliorer la structure generale du document, jugee trop dispersee et peu
    pedagogique.
- Modifications:
  - ajout d'une section `Plan du document` juste apres l'objectif;
  - clarification du parcours de lecture en quatre niveaux:
    - vue d'ensemble par exemples,
    - modele formel,
    - chaine de preuve,
    - lien avec Rocq et l'implementation;
  - renommage de plusieurs sections pour rendre leur role explicite:
    - `Lecture par etapes...` -> `Vue d'ensemble par exemples`,
    - `Notations et structures de base` -> `Modele formel`,
    - `Automate produit et pas locaux` -> `Produit programme x A x G`,
    - `Obligations locales et oracle` -> `Construction des obligations locales`,
    - `Resultats` -> `Chaine de preuve`,
    - `Tracabilite...` -> `Lien avec Rocq et l'implementation actuelle`;
  - ajout de paragraphes de transition au debut des grandes sections pour mieux
    signaler le changement de niveau entre intuition, definitions et preuve.
- Pourquoi:
  - le contenu etait deja riche, mais la progression de lecture etait peu
    lisible: les memes objets reapparaissaient sous plusieurs angles sans que
    leur statut intuitif ou formel soit toujours annonce.
- Validation:
  - recompilation PDF `spec/rocq_oracle_model.tex`: a relancer apres cette passe.

### Mise a jour (2026-03-07, formalisation des extractions d'obligations dans le PDF) - succes
- Demande:
  - s'assurer que tout est defini, formalise et justifie dans le document, et
    en particulier que les extractions d'obligations ne soient plus une simple
    enumeration de familles.
- Modifications:
  - enrichissement de l'etape 6 avec:
    - les quatre roles abstraits (`ObjectiveNoBad`, `CoherencyGoal`,
      `SupportAutomaton`, `SupportUserInvariant`);
    - une intuition explicite pour chacun;
    - quatre operateurs d'extraction intuitifs:
      `Extract_obj`, `Extract_coh`, `Extract_auto`, `Extract_user`;
  - ajout, dans la partie formelle, d'une sous-section
    `Classification et operateurs d'extraction` qui:
    - raffine l'origine abstraite des obligations,
    - formalise l'extraction objective depuis les pas dangereux,
    - formalise l'extraction de coherence depuis les etats/pas atteignables,
    - formalise l'extraction de support automate,
    - formalise l'extraction de support utilisateur,
    - explicite que `Generated` est l'union des images de ces operateurs;
  - mise a jour de la section Rocq/implementation pour faire apparaitre plus
    clairement le role de `ObligationGenSig`, `ObligationTaxonomySig` et
    `ObcAugmentationSig`.
- Pourquoi:
  - la version precedente nommait correctement les familles, mais ne donnait ni
    leur principe generateur, ni leur justification semantique.
- Validation:
  - recompilation PDF `spec/rocq_oracle_model.tex`: a relancer apres cette passe.

### Mise a jour (2026-03-07, etude comparative article LTL / Kairos) - succes
- Demande:
  - produire une etude comparative poussee entre l'article
    `Verification de proprietes LTL sur des programmes C par generation
    d'annotations` et l'architecture actuelle de Kairos.
- Travail realise:
  - lecture des fichiers de reference du chantier Kairos:
    - `rocq/README.md`,
    - `rocq/PROOF_STATUS.md`,
    - `spec/rocq_oracle_model.tex`;
  - extraction partielle du PDF fourni:
    - identification du titre, des auteurs et de la these centrale;
    - reperage de notations lisibles autour d'un automate
      `A = <Q, q0, R>`, de la synchronisation `sync(A, sigma, i)` et d'une
      decomposition des annotations en `DeclA`, `TransA`, `SyncA`;
  - redaction de deux fichiers a la racine du depot:
    - `OBJECTIF_METHODOLOGIE_2026-03-07_ETUDE_COMPARATIVE_ARTICLE_LTL_KAIROS.md`,
    - `ETUDE_COMPARATIVE_2026-03-07_LTL_ANNOTATIONS_ET_KAIROS.md`.
- Resultat:
  - l'etude montre une convergence forte de fond:
    `propriete temporelle -> automate -> contraintes locales -> backend externe`;
  - elle explicite aussi les points ou Kairos va plus loin:
    - produit explicite `programme x A x G`,
    - noyau interne prouve en Rocq,
    - separation nette entre noyau prouve et hypotheses externes.
- Limite:
  - l'extraction texte du PDF est partiellement degradee par l'encodage des
    fontes; l'etude s'appuie donc sur les parties lisibles et sur les objets
    centraux effectivement recuperables.

### Mise a jour (2026-03-07, correction de l'asymetrie article / Kairos dans l'etude comparative) - succes
- Demande:
  - rendre plus explicites deux differences sous-estimees dans la premiere
    version de l'etude:
    - l'article semble raisonner sur des traces de programme/appels plus pauvres
      que les traces reactives de Kairos;
    - Kairos gere explicitement une specification d'entree via l'automate `A`.
- Modifications:
  - renforcement du document comparatif pour distinguer:
    - convergence de methode,
    - divergence d'objet semantique;
  - ajout d'une section claire sur:
    - `traces de controle/programme` vs `traces reactives d'execution`,
    - `une propriete` vs `specification d'entree + garantie`;
  - reformulation de la conclusion pour eviter toute impression d'equivalence
    trop forte entre l'article et Kairos.
- Pourquoi:
  - sans cette correction, le document pouvait laisser croire que l'article et
    Kairos traitent essentiellement le meme probleme, alors que Kairos vise un
    cadre assume/guarantee sur traces reactives plus riche.

### Mise a jour (2026-03-07, approfondissement de la methode et des resultats de l'article) - succes
- Demande:
  - ajouter a l'etude comparative une section expliquant plus finement la
    methode de l'article et les resultats obtenus.
- Travail realise:
  - nouvelle extraction ciblee des pages centrales et finales du PDF fourni via
    `pypdf` dans un environnement virtuel temporaire;
  - elements lisibles identifies:
    - pipeline `LTL -> LTL2BA -> automate de Büchi simplifiee -> calcul des annotations -> Frama-C/Jessie/Why/proveurs`;
    - type de synchronisation `sync : BUCHI x PATH x N -> 2^Q`;
    - decomposition `AnnA = DeclA union TransA union SyncA`;
    - exemples avec observables du type `Call(...)`, `Return(...)`, `status`, `cpt`.
- Ajout dans l'etude:
  - une section `Methode de l'article, reconstruite plus finement`;
  - une section `Resultats obtenus par l'article`;
  - une explication explicite du fait que l'article fait bien de la verification
    deductive sur le programme annote, mais a travers un encodage de
    synchronisation automate/programme.
- Prudence maintenue:
  - les formulations sont volontairement nuancees quand l'extraction du PDF ne
    permet pas d'attribuer avec certitude un theoreme exact ou une propriete
    trop precise.

### Mise a jour (2026-03-07, extension de l'etude comparative aux outils voisins de Kairos) - succes
- Demande:
  - ajouter une comparaison poussee entre Kairos et plusieurs outils voisins:
    `Aorai`, `CaFE`, `AGREE`, `Kind 2`, `CoCoSpec`, `Copilot`.
- Travail realise:
  - collecte de sources officielles ou primaires pour chaque outil:
    - pages Frama-C pour `Aorai` et `CaFE`,
    - rapport technique `AGREE`,
    - site et papiers `Kind 2` / `CoCoSpec`,
    - site officiel `Copilot`;
  - ajout d'une section dediee dans
    `ETUDE_COMPARATIVE_2026-03-07_LTL_ANNOTATIONS_ET_KAIROS.md` distinguant:
    - outils de preuve de programme annote,
    - outils de contrats pour systemes reactifs,
    - outils de monitoring;
  - pour chaque outil:
    - objet traite,
    - technique principale,
    - proximite avec Kairos,
    - difference structurante;
  - ajout d'un tableau de positionnement et d'un bilan synthetique.
- Point important:
  - la comparaison ne cherche pas a lisser les differences; elle explicite au
    contraire que Kairos se situe a l'intersection de trois dimensions rarement
    reunies:
    - preuve de programme/systeme reactif,
    - hypothese d'entree explicite `A` et garantie `G`,
    - produit semantique central `programme x A x G` avec reduction locale
      mechanisee.

### Mise a jour (2026-03-07, refonte structurelle du papier mathematique Rocq) - succes
- Demande:
  - reprendre `spec/rocq_oracle_model.tex` a partir des remarques accumulees dans
    `spec/ROCQ_PAPER_REMARKS.md`, puis restructurer le document comme un article
    de recherche plus coherent et plus complet.
- Travail realise:
  - abandon de l'ancienne structure separee ``intuitive puis formelle'';
  - reecriture complete du document selon une progression unique:
    - introduction et objectif,
    - definition du programme reactif,
    - semantique sur flux,
    - automates de surete,
    - produit `programme x A x G`,
    - pas dangereux,
    - generation pseudo-algorithmique des obligations,
    - chaine de preuve,
    - lien avec Rocq et l'implementation,
    - discussion et conclusion;
  - ajout d'une definition formelle du programme incluant:
    - transitions relationnelles,
    - invariants utilisateur d'etat,
    - contrats utilisateur de transition;
  - ajout d'une presentation explicite de la semantique sur flux comme equation
    coinductive / copoint fixe;
  - remplacement de la notation imperative dans les exemples par une notation
    relationnelle (`m' = x`, `y = m`, etc.);
  - reecriture des automates graphiques avec mise en page plus aeree;
  - ajout d'une section de generation pseudo-algorithmique couvrant les cas:
    - pas dangereux,
    - pas sure,
    - pas allant vers `bad_A`,
    - obligations de coherence/support,
    - reinjection des annotations utilisateur;
  - recentrage de toute la presentation des obligations autour du produit et de
    la notion de pas dangereux.
- Validation:
  - recompilation PDF reussie avec:
    `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
  - fichier genere:
    `spec/rocq_oracle_model.pdf`
- Remarque:
  - il reste seulement des warnings LaTeX mineurs sur le placement des floats,
    sans erreur de compilation.

### Mise a jour (2026-03-07, separation explicite programme / specification) - succes
- Demande:
  - corriger la presentation pour que `A`, `G` et les invariants de noeud ne
    fassent pas partie de la definition primitive du programme;
  - aligner dans ce sens le papier, l'implementation et Rocq.
- Travail realise:
  - dans le papier `spec/rocq_oracle_model.tex`:
    - remplacement de la definition du programme par une definition purement
      syntaxe/semantique;
    - introduction explicite d'une specification associee
      `Phi = (A, G, Inv)`;
    - suppression de `UserStepInv` comme composante primitive;
    - clarification du fait que les obligations de transition issues des
      invariants de noeud sont derivees par projection backend;
  - dans l'implementation OCaml:
    - ajout d'une vue explicite `node_semantics` / `node_specification` dans
      `lib_v2/runtime/core/ast/ast.mli` et `ast.ml`;
    - ajout des accesseurs `semantics_of_node` et `specification_of_node`;
    - adaptation de `automata_spec.ml` et `instrumentation.ml` pour consommer la
      vue specification quand ils manipulent assumptions/guarantees/invariants;
  - dans Rocq:
    - ajout des records conceptuels `ProgramSemantics` et `NodeSpecification`
      dans `rocq/KairosOracle.v`;
    - conservation de l'API existante via `program_part` et
      `specification_part`, pour ne pas casser les developments existants;
    - ajustement des fichiers Rocq qui dependaient de l'ordre implicite des
      parametres generalises (`cfg_at`, `ctx_at`, `run_trace`,
      `run_product_state`).
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build` OK
  - recompilation Rocq complete OK
  - recompilation PDF `spec/rocq_oracle_model.tex` OK

### Mise a jour (2026-03-07, propagation de la vue `node_specification` dans les passes OCaml) - succes
- Demande:
  - pousser plus loin la separation `programme` / `specification` dans
    l'implementation, au-dela du seul AST et du middle-end immediat.
- Travail realise:
  - remplacement d'acces directs a `n.assumes`, `n.guarantees` et
    `n.attrs.invariants_state_rel` par `Ast.specification_of_node n` dans des
    passes supplementaires:
    - `lib_v2/runtime/core/ast/collect.ml`
    - `lib_v2/runtime/core/ast/ast_invariants.ml`
    - `lib_v2/runtime/core/logic/fo/fo_specs.ml`
    - `lib_v2/runtime/middle_end/automata_generation/automata_generation.ml`
    - `lib_v2/runtime/middle_end/automata_generation/automata_atoms.ml`
    - `lib_v2/runtime/middle_end/instrumentation/instrumentation.ml`
    - `lib_v2/runtime/backend/emit.ml`
    - `lib_v2/runtime/backend/emit/dot_emit.ml`
    - `lib_v2/runtime/backend/obc/obc_emit.ml`
    - `lib_v2/runtime/backend/obc/obc_ghost_instrument.ml`
    - `lib_v2/runtime/backend/why/why_contracts.ml`
    - `lib_v2/runtime/backend/why/why_env.ml`
    - `lib_v2/runtime/backend/why/why_stage.ml`
    - `lib_v2/runtime/frontend/parse/ast_dump.ml`
  - conservation volontaire de certains acces directs dans
    `contract_coherency.ml`, ou l'on construit justement la partie
    `invariants_state_rel` de la specification.
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build` OK

### Mise a jour (2026-03-07, separation explicite dans `abstract_model`) - succes
- Demande:
  - faire porter explicitement la decomposition `partie programme` /
    `partie specification` jusque dans les types intermediaires de
    l'instrumentation.
- Travail realise:
  - extension de `lib_v2/runtime/middle_end/instrumentation/abstract_model.mli`
    et `.ml` avec:
    - `node_semantics = Ast.node_semantics`
    - `node_specification = Ast.node_specification`
    - champs explicites `semantics` et `specification` dans `Abs.node`;
  - mise a jour de `of_ast_node` / `to_ast_node` pour conserver cette
    decomposition lors des conversions;
  - adaptation de l'instrumentation pour lire directement
    `n.specification.spec_assumes`,
    `n.specification.spec_guarantees`,
    `n.specification.spec_invariants_state_rel`
    dans le contexte abstrait;
  - adaptation du rendu texte de `abstract_model` pour utiliser les champs
    `semantics` / `specification` au lieu des duplications plates.
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build` OK

### Mise a jour (2026-03-07, suppression des champs plats dans `Abs.node`) - succes
- Demande:
  - supprimer la redondance residuelle dans `Abs.node` pour imposer
    effectivement l'usage de la decomposition
    `semantics/specification`.
- Travail realise:
  - reduction du type `Abs.node` dans
    `lib_v2/runtime/middle_end/instrumentation/abstract_model.mli`
    et `.ml` aux seuls champs:
    - `semantics`
    - `specification`
    - `trans`
    - `attrs`;
  - suppression des anciens doublons plats
    (`nname`, `inputs`, `outputs`, `instances`, `locals`, `states`,
    `init_state`, `assumes`, `guarantees`);
  - reconstruction complete du `Ast.node` cible dans `to_ast_node`
    a partir de `n.semantics` et `n.specification`;
  - adaptation des consommateurs de `Abs.node`, notamment dans:
    - `lib_v2/runtime/middle_end/instrumentation/instrumentation.ml`
    - `lib_v2/runtime/middle_end/product/product_build.ml`
    - `lib_v2/runtime/middle_end/product/product_contracts.ml`
    - `lib_v2/runtime/pipeline/pipeline.ml`
    - `bin/dev/probe_vc.ml`;
  - verification par recherche que les acces restants du type
    `.inputs`, `.locals`, `.states`, `.assumes`, etc. concernent
    principalement `Ast.node`, ce qui est attendu.
- Resultat:
  - la separation `programme` / `specification` n'est plus seulement
    conceptuelle dans `abstract_model`; elle est imposee par le type.
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build` OK

### Mise a jour (2026-03-07, invariants sur contexte de trace) - succes
- Demande:
  - faire refleter a tous les niveaux (Rocq, implementation, PDF) que:
    - la semantique du programme reste locale;
    - l'historique appartient a la trace d'execution;
    - `A`, `G` et les invariants de noeud s'interpretent sur des contextes de
      trace, puis sont compiles finiment dans les backends.
- Travail realise:
  - refactorisation de `rocq/KairosOracle.v`:
    - `spec_node_inv` et `node_inv` ne portent plus sur `State -> Mem -> Prop`
      mais sur `StepCtx -> Prop`;
    - suppression du schema `node_inv_init/node_inv_preserved` au profit d'une
      hypothese primitive `node_inv_valid_on_run : forall u k, node_inv (ctx_at u k)`;
    - adaptation des obligations et du theoreme
      `oracle_conditional_correctness_with_node_inv`;
  - adaptation de `rocq/KairosModularIntegration.v` au nouveau type de
    `node_inv` et au nouvel ordre des parametres implicites de `GeneratedBy`;
  - clarification de l'implementation OCaml:
    - commentaire de `node_specification` dans `lib_v2/runtime/core/ast/ast.mli`
      pour expliciter que les invariants de specification vivent sur le contexte
      de trace via `HNow/HPreK`;
    - commentaire correspondant dans
      `lib_v2/runtime/middle_end/instrumentation/abstract_model.mli`;
    - commentaire dans
      `lib_v2/runtime/backend/obc/obc_ghost_instrument.ml` pour marquer
      `__pre_k...` comme artefacts de compilation backend;
  - reecriture du papier `spec/rocq_oracle_model.tex`:
    - definition explicite de `ctx_u(k)` comme contexte local derive de la
      trace;
    - invariants de noeud de type `S -> P(TickCtx -> Bool)` au lieu de
      `S -> P(M -> Bool)`;
    - explication que `prev/pre_k` sont interpretes sur la trace puis compiles
      par memoires auxiliaires finies.
- Resultat:
  - le modele mathématique raconte maintenant la meme histoire que le code:
    la specification parle du passe via la trace, pas via une extension
    primitive de l'etat du programme.
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build` OK
  - compilation Rocq complete OK via `rocq makefile` + `make -f rocq_build.mk -j2`
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK

### Mise a jour (2026-03-07, passe editoriale sur le papier Rocq) - succes
- Demande:
  - reprendre le papier a partir des remarques accumulees, puis archiver les
    remarques traitees dans un fichier d'historique.
- Travail realise:
  - simplification de la presentation du pas deterministe dans
    `spec/rocq_oracle_model.tex`:
    - suppression du doublon artificiel `select_P` / `step_P`;
    - introduction de la notation lisible
      `((s,m),i) ->_P^t ((s',m'),o)`;
  - clarification de `TickCtx`:
    - definition concrete comme n-uplet
      `(k, cfg_courante, entree, sortie, cfg_suivante)`;
    - explication explicite de `ctx_u(k)` comme contexte local extrait de
      l'execution;
  - simplification de la presentation coinductive:
    - elimination des notations opaques `o_P` / `rho'` non introduites;
    - remplacement par un enonce direct sur le premier pas et sur le suffixe
      `u^(1)`;
  - archivage du lot de remarques traitees dans
    `spec/ROCQ_PAPER_REMARKS_HISTORY_2026-03-07.md`;
  - reinitialisation du tampon courant
    `spec/ROCQ_PAPER_REMARKS.md`.
- Validation:
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK

### Mise a jour (2026-03-07, passe de conformite Rocq du papier) - succes
- Demande:
  - reprendre une nouvelle fois le PDF mathematique pour integrer les remarques
    recentes et supprimer les divergences restantes avec la formalisation Rocq.
- Travail realise:
  - clarification du debut du papier:
    - `Inv` presente comme invariant agrege unique
      `S -> TickCtx -> Bool`;
    - introduction plus nette des automates de surete, de leur run et de la
      condition de reconnaissance;
    - explication des variables courantes et de `prev/pre_k` via une
      interpretation abstraite sur `TickCtx`;
  - la notation flechee `->` est maintenant la notation principale pour les pas
    du programme;
  - la section sur le produit a ete corrigee pour coller a Rocq:
    - etat du produit fini `S × Q_A × Q_G`;
    - memoire/entree/sortie deplacees au niveau du pas concret et du matching;
  - reecriture des exemples `delay_int` et `toggle` pour enlever l'idee fausse
    que la memoire ferait partie de l'etat du produit;
  - archivage du lot de remarques traitees dans
    `spec/ROCQ_PAPER_REMARKS_HISTORY_2026-03-07_B.md`;
  - reinitialisation du tampon courant `spec/ROCQ_PAPER_REMARKS.md`.
- Validation:
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK

### Mise a jour (2026-03-07, reprise du tampon courant pour le papier mathematique) - succes
- Demande:
  - reprendre le tampon courant `spec/ROCQ_PAPER_REMARKS.md` et corriger le
    papier mathematique en consequence.
- Travail realise:
  - reecriture du resume:
    - suppression des formules symboliques dans l'abstract;
    - recentrage sur le probleme, la difficulte et l'idee cle du produit
      explicite;
  - reecriture de l'introduction dans un style plus proche d'un article de
    recherche:
    - probleme vise;
    - difficulte technique;
    - idee de solution;
    - role de la preuve Rocq;
  - reecriture de `Contexte local et relation de matching`:
    - motivation explicite de la distinction entre tick concret et pas abstrait;
    - definition factorisee de `ctx(u,k)` en source / observation / cible;
    - explication de `Match` comme pont entre generation statique et execution
      concrete;
    - mise en conformite de la presentation avec `StepCtx`,
      `product_step_realizes_at` et `ctx_matches_ps`;
  - reecriture des sections `delay_int` et `Generation pseudo-algorithmique`:
    - obligation effectivement generee explicitee;
    - instanciation immediate de la procedure generale sur `delay_int`;
    - formes concretes d'obligations affichees dans l'algorithme conceptuel;
    - `Origines abstraites` rederivees des regles de generation;
  - reecriture de la `Chaine de preuve`:
    - hypotheses explicites;
    - enonces plus formels;
    - esquisses de preuve alignees sur
      `bad_local_step_if_G_violated` et `generation_coverage`;
  - archivage du lot traite dans
    `spec/ROCQ_PAPER_REMARKS_HISTORY_2026-03-07_C.md`;
  - reinitialisation du tampon courant `spec/ROCQ_PAPER_REMARKS.md`.
- Validation:
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK
  - warnings residuels:
    - quelques `Overfull \\hbox` mineurs;
    - transformation de certains flottants `h` en `ht`

### Mise a jour (2026-03-07, review critique POPL du papier mathematique) - succes
- Demande:
  - faire une review critique de niveau reviewer POPL sur la forme, le fond, la
    rigueur mathematique, la credibilite des resultats, la coherence des
    enonces et la qualite des preuves;
  - produire une note d'amelioration;
  - appliquer cette note au papier.
- Travail realise:
  - redaction d'une note critique dediee:
    - `spec/POPL_REVIEW_NOTES_2026-03-07.md`;
  - diagnostic principal consigne:
    - sur-affirmation de la partie coinductive;
    - glissement residuel entre `Bool` et predicats semantiques;
    - decalage de signature sur `GeneratedBy`;
    - chaine de preuve encore trop comprimee;
    - traces editoriales de note technique;
    - petit bug de duplication textuelle dans la section `StepCtx`;
  - corrections appliquees dans `spec/rocq_oracle_model.tex`:
    - remplacement de la pseudo-preuve coinductive par une definition primaire
      point par point;
    - lecture coinductive reloguee en remarque;
    - passage des predicats semantiques de `Bool` vers `Prop`;
    - alignement de `GeneratedBy` avec la formalisation Rocq;
    - ajout d'une sous-section explicite separant hypotheses internes et
      hypotheses externes dans la chaine de preuve;
    - ajout d'un lemme de validite des obligations de support invariant;
    - nettoyage editorial des duplications et formulations trop "note interne".
- Validation:
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK
  - warnings residuels:
    - quelques `Overfull \\hbox` mineurs;
    - flottants `h` convertis en `ht`

### Mise a jour (2026-03-07, traduction anglaise du papier mathematique) - succes
- Demande:
  - traduire en anglais le document mathematique dans `spec/`.
- Travail realise:
  - traduction du papier `spec/rocq_oracle_model.tex` du francais vers
    l'anglais;
  - passage de `babel` en anglais;
  - traduction des environnements de theorematiques (`Definition`, `Theorem`,
    `Lemma`, `Remark`);
  - traduction du titre, du resume, de l'introduction, des sections
    mathematiques et des figures/captions;
  - nettoyage des derniers fragments francais residuels dans les exemples et
    les definitions du produit et des obligations.
- Validation:
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK
  - PDF regenere:
    - `spec/rocq_oracle_model.pdf` (`Mar 7 18:53:25 2026`, `416024` octets)
  - warnings residuels:
    - quelques `Overfull \\hbox` mineurs;
    - flottants `h` convertis en `ht`

### Mise a jour (2026-03-07, section technique implementation/Why3 dans le papier) - succes
- Demande:
  - ajouter au papier mathematique une section technique sur :
    - le langage de programmation et de specification de l'implementation;
    - la methode de passage des obligations detaillees vers Why3;
    - ce qui est effectivement envoye a Why3;
    - le resultat recupere et sa signification.
- Travail realise:
  - remplacement de l'ancienne section mixte `Rocq and the Implementation` par
    une section `Implementation Language and Why3 Backend`;
  - ajout d'une presentation de la separation source entre :
    - couche programme (inputs, outputs, variables, etats, transitions);
    - couche specification (assumes, guarantees, invariants de noeud);
  - ajout d'une description du pipeline de projection :
    - analyse du produit;
    - projection backend via `__aut_state` et variables `__pre_k...`;
    - generation OBC/Why3;
    - extraction des taches VC/SMT;
  - ajout d'une sous-section sur l'objet effectivement envoye a Why3;
  - ajout d'une sous-section sur l'interpretation semantique des statuts
    Why3 (`proved`, `invalid`, `unknown`, `timeout`, `failure`).
- Validation:
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK
  - PDF regenere:
    - `spec/rocq_oracle_model.pdf` (`Mar 7 18:58:04 2026`, `422557` octets)
  - warnings residuels:
    - quelques `Overfull \\hbox` mineurs;
    - flottants `h` convertis en `ht`

### Mise a jour (2026-03-07, section related work et bibliographie du papier) - succes
- Demande:
  - ajouter une section `Related Work` detaillee avec comparaison;
  - ajouter la bibliographie associee;
  - maintenir une conclusion coherente.
- Travail realise:
  - ajout d'une section `Related Work` dans `spec/rocq_oracle_model.tex`;
  - structuration de la comparaison par familles:
    - verification temporelle de programmes par annotations (`Aorai`, `CaFE`);
    - verification synchrone assume/guarantee (`AGREE`, `Kind 2`, `CoCoSpec`,
      `Lustre/PVS`);
    - compilation de moniteurs (`Copilot`);
  - ajout d'un paragraphe de positionnement specifique de Kairos;
  - ajout d'une bibliographie integree via `thebibliography`;
  - conservation et verification de la conclusion finale apres insertion des
    nouvelles sections.
- Validation:
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK
  - PDF regenere:
    - `spec/rocq_oracle_model.pdf` (`Mar 7 19:02:08 2026`, `435265` octets)
  - warnings residuels:
    - quelques `Overfull \\hbox` mineurs;
    - un fallback de police monospace en gras dans certains passages;
    - pas d'erreur de citations non resolues

### Mise a jour (2026-03-07, hypotheses de totalite des ticks et statut abstrait de `prev`) - succes
- Demande:
  - signaler dans le papier que le modele abstrait suppose qu'un programme
    calcule toujours un etat suivant, une memoire suivante et une sortie;
  - expliciter qu'en pratique Kairos peut rencontrer blocage par operation
    invalide ou absence d'emission sur une sortie, et que cela doit etre garanti
    par des conditions additionnelles;
  - presenter `prev` et constructions analogues comme de simples instanciations
    possibles du cadre abstrait sur l'historique, pas comme partie primitive du
    modele.
- Travail realise:
  - ajout d'une remarque de totalite juste apres la definition du pas
    deterministe du programme;
  - ajout d'une remarque `Abstract History Interface` et transformation de la
    definition de `prev` en `Example Instantiation of History`;
  - re-ecriture de la remarque semantique pour faire de `prev` une intuition de
    niveau langage, non un constituant du noyau abstrait;
  - ajout, dans la section Why3/backend, d'un paragraphe sur les obligations
    backend supplementaires necessaires pour garantir :
    - absence de blocage;
    - definedness des operations;
    - emission totale des sorties.
- Validation:
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK
  - PDF regenere:
    - `spec/rocq_oracle_model.pdf` (`Mar 7 19:02:40 2026`, `438775` octets)
  - warnings residuels:
    - quelques `Overfull \\hbox` mineurs;
    - flottants `h` convertis en `ht`

### Mise a jour (2026-03-07, exhaustivite des transitions comme condition structurelle) - succes
- Demande:
  - traiter explicitement le cas ou aucun filtre de transition n'est actif pour
    l'etat courant;
  - ne pas presenter cela comme une propriete semantique globale a prouver,
    jugée trop forte ou impraticable;
  - clarifier qu'un etat puit avec sortie implicite n'est pas une bonne
    solution dans le modele abstrait.
- Travail realise:
  - ajout d'une remarque `Exhaustiveness of Transition Filtering` dans la partie
    semantique;
  - position retenue dans le papier:
    - l'exhaustivite du filtrage par etat/garde/memoire est une condition de
      bien-formation structurelle des programmes concrets;
    - cette condition peut etre obtenue, en pratique, par exhaustivite
      syntaxique ou branche par defaut au niveau du langage source;
    - on ne l'integre pas via un etat puit semantique, car cela demanderait de
      fixer une sortie observable non neutre;
  - re-ecriture de la section backend:
    - remplacement de l'idee d'``obligations de totalite'' par celle de
      `side conditions`/checks garantissant que le programme concret appartient
      bien au fragment total suppose par le modele.
- Validation:
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK
  - PDF regenere:
    - `spec/rocq_oracle_model.pdf` (`Mar 7 19:27:42 2026`, `438819` octets)
  - warnings residuels:
    - quelques `Overfull \\hbox` mineurs;
    - flottants `h` convertis en `ht`

### Mise a jour (2026-03-07, temoins explicites d'aretes `A/G` dans le produit OCaml) - succes
- Demande:
  - rapprocher l'IR produit de l'implantation de la structure de `ProductStep`
    cote Rocq;
  - conserver explicitement, dans les pas du produit, les aretes d'automates
    d'hypothese et de garantie, au lieu de ne garder que leurs gardes logiques;
  - ne pas traiter dans cette passe les garanties de totalite/exhaustivite,
    signalees comme non accessibles pour l'instant.
- Travail realise:
  - enrichissement de `lib_v2/runtime/middle_end/product/product_types.mli` et
    `lib_v2/runtime/middle_end/product/product_types.ml`:
    - ajout de `automaton_edge = Automaton_engine.transition`;
    - ajout des champs `assume_edge` et `guarantee_edge` dans `product_step`;
    - ajout des memes temoins dans `pruned_step`;
  - adaptation de
    `lib_v2/runtime/middle_end/product/product_build.ml`:
    - conservation des triples complets `(src, guard, dst)` pour les automates;
    - propagation de ces temoins dans tous les pas explores et tous les pas
      elimines (`pruned`);
  - adaptation de
    `lib_v2/runtime/middle_end/product/product_debug.ml`:
    - rendu texte des pas et des prunings avec affichage des aretes `A[src->dst]`
      et `G[src->dst]`;
    - enrichissement du `product_dot` avec les memes temoins, pour rendre le
      graphe du produit plus interpretable.
- Resultat:
  - l'implantation conserve maintenant la provenance combinatoire exacte des pas
    `A/G` sans perdre les gardes deja utilises pour la generation des
    obligations;
  - cette passe ameliore la tracabilite et rapproche l'IR OCaml du modele Rocq,
    sans alourdir la logique de generation actuelle.
- Validation:
  - `opam exec --switch=5.4.1+options -- dune build` OK

### Mise a jour (2026-03-07, simplification de la tracabilite Rocq des obligations) - succes
- Demande:
  - supprimer dans la formalisation Rocq les elements de tracabilite
    `obligation -> source` qui ne sont pas necessaires aux preuves;
  - conserver uniquement ce qui reste utile a la taxonomie et aux couches
    modulaires.
- Analyse:
  - dans le noyau `KairosOracle`, la relation `GeneratedBy` transportait
    `origin`, `Trans Paut` et `Obligation`;
  - les preuves principales n'exploitent pas le temoin de transition
    `Trans Paut`;
  - en revanche, `origin` reste utile comme etiquetage logique des obligations
    pour les signatures modulaires et la taxonomie.
- Travail realise:
  - simplification de `rocq/KairosOracle.v`:
    - `GeneratedBy` passe de `origin -> Trans Paut -> Obligation -> Prop`
      a `origin -> Obligation -> Prop`;
    - `Generated` passe de `exists o t, ...` a `exists o, ...`;
    - adaptation des preuves `generated_node_inv_obligation` et
      `generation_coverage`;
  - simplification coherente du pont modulaire dans
    `rocq/KairosModularIntegration.v`, qui n'a plus a existentialiser un
    temoin de transition.
- Resultat:
  - la formalisation conserve la provenance logique minimale des obligations
    via `origin`;
  - le temoin de transition, qui n'intervenait pas dans les preuves de
    correction, a ete retire du noyau.
- Validation:
  - `opam exec --switch=5.4.1+options -- rocq makefile -R rocq '' rocq/*.v rocq/*/*.v -o rocq_build.mk` OK
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK

### Mise a jour (2026-03-07, derivation Rocq de `node_inv` par obligations) - succes
- Demande:
  - ne plus supposer `node_inv` valide sur toute execution;
  - faire refleter dans Rocq le schema reel de l'implantation, ou la validite
    des invariants de noeud vient d'une initialisation et d'une preservation
    locale via obligations generees.
- Probleme constate:
  - `rocq/KairosOracle.v` postulait
    `node_inv_valid_on_run : forall u k, node_inv ...`;
  - cela court-circuitait exactement le raisonnement inductif backend
    `requires Inv(src)` / `ensures Shift(Inv(dst))` present dans
    l'implantation.
- Travail realise:
  - suppression de l'hypothese globale `node_inv_valid_on_run` dans
    `rocq/KairosOracle.v`;
  - introduction d'une formule FO representant l'invariant de noeud:
    - `node_inv_fo : State -> FO`;
    - `node_inv_fo_correct : eval_fo ctx (node_inv_fo s) <-> node_inv s ctx`;
  - ajout d'une obligation initiale :
    - `init_node_inv_obligation`;
  - reinterpretation de l'obligation `NodeInvariant` comme obligation locale de
    preservation:
    - si un contexte matche un pas produit et si `node_inv` tient au tick
      courant, alors `shift_fo 1 (node_inv_fo dst)` tient au tick courant;
  - preuve nouvelle:
    - `init_node_inv_holds`;
    - `node_inv_holds_on_run`, par induction sur les ticks, en combinant:
      - validite oracle des obligations generees;
      - `ctx_matches_ps` pour le pas realise;
      - `shifted_formula_transfers_to_successor`;
      - correction `node_inv_fo_correct`.
  - ajustement du pont modulaire dans `rocq/KairosModularIntegration.v` pour
    exposer `node_inv_fo` et `node_inv_fo_correct`, et pour appeler
    `GeneratedBy` avec ses nouveaux parametres.
- Resultat:
  - le noyau Rocq est maintenant plus proche de l'implantation sur ce point:
    l'invariant n'est plus postule globalement, il est rederive a partir
    d'obligations generees et validees par l'oracle;
  - cela rapproche la formalisation du schema de coherence des invariants
    utilise par le backend.
- Validation:
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK

### Mise a jour (2026-03-07, architecture des obligations en quatre categories) - succes
- Demande:
  - formaliser clairement l'architecture de preuve autour de quatre categories
    d'obligations:
    - `NoBad`;
    - `InitialGoal`;
    - `UserInvariant`;
    - `AutomatonSupport`;
  - documenter cette architecture dans un fichier dedie;
  - mettre le papier mathematique en coherence avec cette decomposition;
  - commencer le refactoring Rocq pour faire apparaitre explicitement ces
    categories.
- Analyse retenue:
  - `NoBad` est l'objectif de surete proprement dit;
  - `InitialGoal` est le cas de base de l'induction de coherence;
  - `UserInvariant` propage les invariants utilisateur via
    `requires Inv(src)` / `ensures Shift(Inv(dst))`;
  - `AutomatonSupport` justifie les faits automates ajoutes aux preconditions
    locales (compatibilite moniteur et projection `A/G` du produit);
  - le solveur ne peut pas prouver un `NoBad` local en isolation: il faut
    rendre explicite la validite des hypotheses locales qui l'aident.
- Travail realise:
  - ajout du document
    `rocq/proof_architecture.md`, avec:
    - les quatre categories;
    - leur role exact;
    - leur correspondance avec les familles fines du pipeline OCaml;
    - le lien avec la taxonomie abstraite Rocq;
  - mise a jour de `spec/rocq_oracle_model.tex`:
    - reecriture de la section sur l'algorithme conceptuel;
    - remplacement de l'ancienne taxonomie trop declarative par la decomposition
      en quatre categories;
    - explication detaillee du role inductif de `InitialGoal`,
      `UserInvariant`, `AutomatonSupport` et `NoBad`;
  - refactoring de `rocq/KairosOracle.v`:
    - l'origine concrete des obligations devient:
      `ObjectiveNoBad | InitialGoal | UserInvariant | AutomatonSupport`;
    - suppression de `classify_product_step`;
    - ajout de `support_automaton_fo : ProductStep -> FO`;
    - ajout de `support_automaton_obligation`;
    - `gen_from_product_step` genere maintenant explicitement:
      - l'objectif `NoBad`;
      - le support automate;
      - la propagation d'invariant utilisateur;
    - `init_generated_items` porte explicitement le cas `InitialGoal`;
    - ajout du lemme `generated_support_automaton_obligation`;
  - mise a jour de `rocq/KairosModularIntegration.v` pour exposer
    `support_automaton_fo` et pour suivre la nouvelle signature de
    `GeneratedBy`.
- Resultat:
  - l'architecture documentaire et le noyau Rocq parlent maintenant des memes
    quatre categories;
  - le support automate est explicite dans Rocq, meme si sa discipline de
    propagation n'est pas encore reconstruite aussi finement que dans
    l'implantation;
  - l'ancienne originologie ad hoc (`Coherency`, `NodeInvariant`, etc.) a ete
    remplacee, dans le noyau concret, par une taxonomie plus proche du vrai
    schema de preuve.
- Validation:
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK

### Mise a jour (2026-03-07, propagation inductive du support automate en Rocq) - succes
- Demande:
  - aller au-dela de la simple introduction de la categorie
    `AutomatonSupport`;
  - reconstruire en Rocq une vraie discipline de propagation, analogue a celle
    utilisee par l'implantation pour justifier les preconditions automates.
- Travail realise:
  - enrichissement de `rocq/KairosOracle.v`:
    - `support_automaton_fo` n'est plus indexe par `ProductStep` mais par
      `ProductState`, ce qui permet de raisonner par propagation d'etat produit;
    - `prod_obligation` devient une obligation objective sous hypotheses
      locales explicites:
      - invariant utilisateur courant;
      - support automate courant;
    - ajout de `init_support_automaton_obligation`;
    - `support_automaton_obligation` devient une vraie obligation de
      preservation:
      - si `ctx` matche un pas produit;
      - et si le support courant vaut;
      - alors la version decalee du support de l'etat cible vaut;
    - ajout des lemmes:
      - `product_select_at_from`;
      - `run_product_state_0`;
      - `realized_step_target_matches_run_product_successor`;
      - `generated_init_support_automaton_obligation`;
      - `init_support_automaton_holds`;
      - `support_automaton_holds_on_run`.
  - adaptation de `generation_coverage`:
    - l'obligation `NoBad` n'est plus traitee comme formule nue;
    - elle est maintenant montree fausse au tick dangereux en utilisant:
      - `node_inv_holds_on_run`;
      - `support_automaton_holds_on_run`;
      - le `Match` du pas realise.
  - mise a jour de `rocq/KairosModularIntegration.v`:
    - `support_automaton_fo` expose maintenant une formule sur
      `ProductState`, coherente avec le noyau.
  - mise a jour documentaire:
    - `rocq/proof_architecture.md`;
    - `spec/rocq_oracle_model.tex`
    pour refleter que Rocq reconstruit maintenant aussi la propagation
    abstraite du support automate.
- Resultat:
  - le noyau Rocq ne se contente plus d'etiqueter `AutomatonSupport`;
  - il prouve maintenant que ces faits de support se propagent le long de
    l'execution, au meme niveau abstrait que les invariants utilisateur;
  - la difference residuelle avec l'implantation est surtout une difference de
    finesse interne (`monitor compatibility` vs `state-aware assumption
    support`), pas une absence de schema inductif.
- Validation:
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK
## 2026-03-07

### Unification de la taxonomie des obligations en quatre familles

- Vérification de l’état courant :
  - Rocq portait déjà les quatre origines `ObjectiveNoBad | InitialGoal | UserInvariant | AutomatonSupport` dans `KairosOracle.v`.
  - L’interface Rocq `rocq/obligations/ObligationTaxonomySig.v` était restée sur une ancienne taxonomie (`CoherencyGoal`, `SupportUserInvariant`, etc.), donc il y avait un vrai décalage conceptuel.
  - L’implémentation OCaml exposait seulement la taxonomie fine de backend (`FamNoBadRequires`, `FamCoherencyRequires`, etc.), sans projection explicite vers les quatre catégories conceptuelles.

- Correction Rocq :
  - refactorisation de `rocq/obligations/ObligationTaxonomySig.v` pour aligner la taxonomie abstraite sur les quatre catégories :
    - `ObjectiveNoBad`
    - `InitialGoal`
    - `UserInvariant`
    - `AutomatonSupport`
  - mise à jour de `rocq/obligations/ObcAugmentationSig.v` pour relier les familles fines OBC à ces quatre catégories ;
  - mise à jour de `rocq/obligations/ObligationStratifiedSig.v` pour refléter les nouvelles phases ;
  - mise à jour des noyaux `rocq/kernels/ObjectiveSafetyKernel.v` et `rocq/kernels/SupportNonBlockingKernel.v` pour supprimer les références à l’ancienne notion de `Coherency`.

- Correction implémentation :
  - enrichissement de `lib_v2/runtime/pipeline/obligation_taxonomy.{ml,mli}` :
    - ajout d’un type `category` à quatre cas (`CatNoBad`, `CatInitialGoal`, `CatUserInvariant`, `CatAutomatonSupport`) ;
    - ajout d’une projection `category_of_family` depuis les familles fines du backend ;
    - séparation dans les résumés entre :
      - catégories générées conceptuelles,
      - familles fines backend ;
    - exclusion explicite de `transition_requires` / `transition_ensures` des quatre catégories générées.

- Mise à jour documentation :
  - `rocq/proof_architecture.md` réaligné sur la taxonomie à quatre catégories ;
  - `spec/rocq_oracle_model.tex` mis à jour pour expliquer que :
    - Rocq et le noyau conceptuel travaillent avec quatre catégories ;
    - l’implémentation conserve en plus une taxonomie fine de backend ;
    - les contrats utilisateur de transition ne font pas partie des obligations générées par l’architecture locale.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- dune build` OK ;
  - recompilation LaTeX relancée après mise à jour du papier ;
  - recompilation Rocq à relancer avec régénération du makefile pour éviter un faux positif `make: Nothing to be done`.

### Synthèse architecture oracle / triplets de Hoare / obligations initiales

- Analyse de deux points d’architecture :
  1. le validateur externe ne devrait pas être modélisé comme vérifiant une obligation sémantique `StepCtx -> Prop`, mais plutôt des objets de preuve de type triplets de Hoare attachés au code des transitions ;
  2. les obligations initiales doivent couvrir à la fois l’initialisation des invariants utilisateur et celle des faits de support automate.

- Constat important :
  - le dépôt contenait déjà une brique Rocq adaptée dans
    `rocq/obligations/TransitionTriplesBridge.v` ;
  - l’implémentation OCaml fonctionne déjà essentiellement comme un backend de contrats de transition / Why3, pas comme un simple validateur de formules ;
  - Rocq possède déjà `init_node_inv_obligation` et `init_support_automaton_obligation`.

- Résultat :
  - rédaction d’une synthèse détaillée dans
    `rocq/oracle_hoare_triplets_synthesis.md` ;
  - position retenue :
    - conserver les clauses sémantiques générées comme objets du noyau de preuve ;
    - insérer entre elles et l’outil externe une couche de bundles de triplets de Hoare groupés par transition programme ;
    - garder les quatre catégories conceptuelles ;
    - expliciter que `InitialGoal` couvre deux sous-cas :
      - initialisation de l’invariant utilisateur,
      - initialisation du support automate.

- Décalage relevé côté implémentation :
  - l’initialisation de l’invariant utilisateur est déjà explicite via `coherency_goals` ;
  - l’initialisation du support automate est aujourd’hui surtout implicite via l’état initial `__aut_state = Aut0` dans le backend Why3 ;
  - il faudra la rendre explicite dans la prochaine passe de refactoring.

- Nouveau point d’architecture intégré à la synthèse :
  - la propagation des invariants utilisateur et celle des faits de support automate ne doivent pas être modélisées comme deux couches de preuve indépendantes ;
  - elles doivent former un bloc unique de propagation de support, car chacune peut être nécessaire pour prouver l’autre au niveau des obligations de transition ;
  - même chose au niveau initial : les clauses d’initialisation invariant/support automate doivent vivre dans les mêmes objets de preuve helper/init.

- Synthèse consolidée :
  - remplacement de la note précédente par une synthèse plus nette dans
    `rocq/oracle_hoare_triplets_synthesis.md` ;
  - découpage retenu :
    - `Safety`
      - `NoBad`
    - `Helper`
      - `InitGoal`
      - `Propagation`
  - les sous-familles `UserInvariant` et `AutomatonSupport` restent utiles pour classifier les clauses générées, mais ne doivent pas être séparées en bundles de preuve distincts ;
  - le validateur externe doit viser des bundles de triplets de Hoare par transition programme, avec provenance fine des clauses pour ne pas perdre l’information des arêtes du produit.

### Portage concret de l’architecture Safety/Helper et du bridge Hoare

- Réalignement Rocq :
  - `rocq/interfaces/ExternalValidationAssumptions.v` enrichi avec deux foncteurs :
    - `MakeExternalValidationAssumptionsFromOracleSem`
    - `MakeExternalValidationAssumptionsFromTransitionTriples`
  - but :
    - rendre explicite le chemin canonique
      `clauses sémantiques générées -> bundles Hoare par transition -> tâches encodées -> checker externe -> hypothèses sémantiques du théorème final` ;
    - conserver l’interface finale du théorème de correction inchangée.

- Réalignement blueprint Rocq :
  - `rocq/KairosRefactorBlueprint.v` mis à jour pour exposer aussi
    `MakeExternalValidationAssumptionsFromOracleSem` et
    `MakeExternalValidationAssumptionsFromTransitionTriples`.

- Réécriture de la note d’architecture :
  - `rocq/proof_architecture.md` réécrit pour refléter la position stabilisée :
    - distinction `clauses sémantiques` / `objets de preuve externes` ;
    - un bundle Hoare par transition programme ;
    - découpage de preuve
      `Safety/NoBad` et `Helper/{InitGoal,Propagation}` ;
    - invariants utilisateur et support automate regroupés dans les mêmes bundles helper.

- Réalignement implémentation :
  - `lib_v2/runtime/pipeline/obligation_taxonomy.mli` documente maintenant explicitement que :
    - les quatre labels conceptuels classifient les clauses générées ;
    - la structure de preuve est `Safety` / `Helper` ;
  - `lib_v2/runtime/pipeline/obligation_taxonomy.ml` renomme le bloc de résumé
    `generated categories` en `generated clause families`.

- Réalignement papier :
  - `spec/rocq_oracle_model.tex` mis à jour pour :
    - parler de clauses `NoBad` et de bundles Hoare de transition ;
    - préciser que les clauses helper sont groupées dans les mêmes bundles ;
    - reformuler les hypothèses externes en termes de complétude/soundness des bundles couvrant les clauses générées.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- rocq compile -Q rocq '' rocq/interfaces/ExternalValidationAssumptions.v` OK ;
  - `opam exec --switch=5.4.1+options -- rocq compile -Q rocq '' rocq/integration/AutomataFinalCorrectness.v` OK ;
  - `opam exec --switch=5.4.1+options -- rocq compile -Q rocq '' rocq/KairosRefactorBlueprint.v` OK ;
  - `opam exec --switch=5.4.1+options -- dune build` OK ;
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK.

### Renommage Rocq `Obligation` -> `Clause`

- Motivation :
  - éviter la confusion entre :
    - les clauses sémantiques générées par le produit ;
    - les vraies obligations externes, qui sont des bundles/triplets de Hoare.

- Refactoring effectué dans les interfaces Rocq :
  - `rocq/obligations/ObligationGenSig.v`
    - `Obligation` renommé en `Clause` ;
  - `rocq/obligations/OracleSig.v`
    - `ObligationValid` renommé en `ClauseValid` ;
  - `rocq/obligations/OracleSemSig.v`
    - `obligation_valid_pointwise` renommé en `clause_valid_pointwise` ;
  - propagation du renommage dans :
    - `TransitionTriplesBridge.v`
    - `HoareExternalBridge.v`
    - `ImplementationValidatorBridge.v`
    - `ObligationTaxonomySig.v`
    - `ObligationStratifiedSig.v`
    - `ObcAugmentationSig.v`
    - `ThreeLayerArchitecture.v`
    - `ThreeLayerFromCore.v`
    - `ExternalValidationAssumptions.v`
    - `AutomataFinalCorrectness.v`
    - `SafetyKernel.v`
    - `ObjectiveSafetyKernel.v`
    - `SupportNonBlockingKernel.v`
    - `KairosOracle.v`
    - `KairosModularArchitecture.v`
    - `KairosModularIntegration.v`
    - `instances/DelayIntInstance.v`.

- Effet architectural :
  - le code Rocq visible parle maintenant de `Clause` pour les objets
    sémantiques locaux ;
  - le mot `obligation` est réservé conceptuellement aux objets externes de
    validation de type Hoare.

- Vérifications :
  - recompilation Rocq complète via
    `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK ;
  - `opam exec --switch=5.4.1+options -- dune build` resté OK après le
    renommage.

### Audit de l’énoncé intentionnel

- Ajout de `rocq/INTENDED_THEOREM_AUDIT.md` pour répondre à la question :
  - “est-ce qu’on prouve encore le bon théorème, et pas seulement un système cohérent ?”

- Structure de l’audit :
  - énoncé intentionnel du projet, indépendamment de Rocq ;
  - énoncé actuellement prouvé ;
  - raffinements jugés conservatifs ;
  - zones de dérive possibles ;
  - liste de questions à trancher explicitement.

- Position retenue dans l’audit :
  - le théorème intentionnel doit être lu comme un théorème conditionnel :
    - si les clauses générées par l’outil sont validées par l’oracle ;
    - si l’entrée satisfait `A` ;
    - alors l’exécution satisfait `G` ;
  - le théorème de haut niveau interne reste
    `AvoidA u -> AvoidG (run_trace u)`,
    mais sous hypothèses externes explicites de validation ;
  - les gros changements récents relèvent surtout du raffinement de la méthode
    de preuve ;
  - clarification importante :
    - au niveau de l’outil, les obligations générées sont déjà des
      triplets/bundles de Hoare ;
    - ce qui reste abstrait dans l’audit est l’encodage exact de ces objets et
      leur validation externe, pas leur nature Hoare elle-même ;
  - les principaux risques de décalage portent maintenant sur :
    - la totalité/déterminisme du tick programme ;
    - l’expressivité réelle de l’historique ;
    - le caractère conditionnel de la validation externe.

### Refactoring du noyau Rocq vers des triples de Hoare relationnels

- Motivation :
  - le noyau clause-centric restait conceptuellement trop faible :
    - les clauses sont les briques de `Pre/Post`,
    - mais les vraies obligations externes doivent être des triples de Hoare
      adaptés à la sémantique relationnelle des transitions.

- Transformation effectuée dans `rocq/KairosOracle.v` :
  - conservation de `Clause := StepCtx -> Prop` comme niveau sémantique local ;
  - ajout de :
    - `triple_target = TripleInit | TripleStep t`
    - `RelHoareTriple`
    - `transition_rel`
    - `TripleValid`
    - triples canoniques :
      - `init_node_inv_triple`
      - `init_support_automaton_triple`
      - `node_inv_triple ps`
      - `support_automaton_triple ps`
      - `no_bad_triple ps`
    - relation de génération :
      - `GeneratedTripleBy`
      - `GeneratedTriple`
    - oracle externe primaire :
      - `TripleOracle`
      - `TripleOracle_sound`
      - `TripleOracle_complete`

- Point important :
  - le noyau n’externalise plus directement les clauses ;
  - il externalise des triples relationnels construits à partir des clauses ;
  - les clauses restent présentes comme composants sémantiques et comme vue
    héritée utilisée par certaines interfaces modulaires.

- Réécriture des preuves principales :
  - `init_node_inv_holds` et `init_support_automaton_holds` dérivés à partir
    des triples initiaux ;
  - `node_inv_holds_on_run` et `support_automaton_holds_on_run` dérivés à
    partir des triples de propagation ;
  - `oracle_conditional_correctness` réécrit pour utiliser un triple
    `no_bad_triple ps` sur le pas dangereux réalisé, au lieu d’un oracle
    direct sur clause.

- Conservation de compatibilité :
  - `generation_coverage` reste disponible comme vue clause-centric, utile pour
    les couches modulaires existantes ;
  - nouveau théorème interne :
    - `triple_generation_coverage`.

- Cohérence avec l’implémentation :
  - le noyau Rocq est maintenant mieux aligné avec le pipeline OCaml, qui
    fonctionne déjà comme générateur de contrats/triples de transition Why3 ;
  - l’implémentation groupe encore ces obligations par transition programme
    pour mutualiser le WP ;
  - le noyau Rocq reste plus fin en générant des triples canoniques par clause
    / pas produit, ce qui est acceptable comme décomposition sémantique
    primitive ;
  - le regroupement par transition est donc lu comme une optimisation/backend
    d’implantation, pas comme une divergence sémantique.

- Documentation mise à jour :
  - `rocq/proof_architecture.md`
  - `rocq/oracle_hoare_triplets_synthesis.md`
  - `rocq/INTENDED_THEOREM_AUDIT.md`
  - `rocq/PROOF_STATUS.md`
  - `spec/rocq_oracle_model.tex`

- Vérifications :
  - `opam exec --switch=5.4.1+options -- rocq compile -Q rocq '' rocq/KairosOracle.v` OK ;
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK ;
  - `opam exec --switch=5.4.1+options -- dune build` OK ;
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK.

### 2026-03-07 — Audit: noyau centré sur la validité des triples

- Demande :
  - retirer l’oracle externe du noyau prouvé ;
  - exprimer directement le théorème central en termes de validité Hoare des
    triples générés ;
  - réaligner l’audit d’intention et le papier sur cette décision.

- Analyse :
  - le noyau utilisait encore une couche `TripleOracle` artificielle ;
  - cela masquait l’intention désormais retenue :
    - les clauses locales servent à construire des triples relationnels ;
    - l’hypothèse du noyau est simplement que tous les triples générés sont
      valides ;
    - la modélisation d’un validateur externe relève d’une couche ultérieure.

- Modifications :
  - dans `rocq/KairosOracle.v` :
    - suppression de `TripleOracle`, `TripleOracle_sound`,
      `TripleOracle_complete` ;
    - introduction de :
      - `GeneratedTripleValid :
         forall ht, GeneratedTriple ht -> TripleValid ht` ;
    - réécriture des lemmes de base et de propagation pour utiliser cette
      hypothèse directe ;
    - introduction du théorème central :
      - `triple_valid_conditional_correctness` ;
    - conservation d’alias de compatibilité :
      - `oracle_conditional_correctness`,
      - `oracle_conditional_correctness_with_node_inv`.
  - dans `rocq/INTENDED_THEOREM_AUDIT.md` :
    - remplacement systématique du récit ``oracle accepte / oracle valide'' par
      ``les triples générés sont valides'' ;
    - clarification que le pont externe est un raffinement futur.
  - dans `spec/rocq_oracle_model.tex` :
    - la section de preuve parle maintenant de validité des triples générés ;
    - le théorème conditionnel ne dépend plus d’un oracle au niveau du noyau
      mathématique.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- rocq compile -Q rocq '' rocq/KairosOracle.v` OK ;
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK ;
  - `opam exec --switch=5.4.1+options -- dune build` OK ;
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK.

- Point de vigilance :
  - certaines couches d’intégration et de bridge parlent encore d’``oracle'' ;
  - cela reste acceptable si on les lit comme raffinements externes et non
    comme partie du noyau mathématique.

### 2026-03-07 — Allègement du chemin principal Rocq

- Demande :
  - rendre la structure Rocq plus lisible ;
  - faire apparaître un chemin principal court autour de `KairosOracle.v` ;
  - reléguer les bridges externes au rang de raffinements optionnels.

- Analyse :
  - `KairosRefactorBlueprint.v` importait trop de couches à la fois, y compris
    des bridges externes non nécessaires à la lecture du noyau ;
  - `README.md` et `PROOF_STATUS.md` présentaient encore
    `ExternalValidationAssumptions` et `AutomataFinalCorrectness` comme files
    centraux, alors que le noyau est maintenant centré sur la validité des
    triples générés ;
  - il manquait un point d’entrée minimal dans l’arbre Rocq.

- Modifications :
  - ajout de `rocq/MainProofPath.v` :
    - point d’entrée minimal exposant les faits centraux :
      - `bad_local_step_if_G_violated`
      - `generation_coverage`
      - `triple_generation_coverage`
      - `triple_valid_conditional_correctness`
  - réécriture de `rocq/KairosRefactorBlueprint.v` :
    - imports réduits au noyau, aux signatures utiles et aux vues légères ;
    - retrait des imports de bridges externes ;
    - commentaire explicite listant les raffinements optionnels exclus ;
  - mise à jour de `rocq/README.md` :
    - nouvelle section `Main Proof Path` ;
    - nouvelle section `Optional Refinement Layers` ;
    - retrait du statut central d’`ExternalValidationAssumptions` ;
  - mise à jour de `rocq/PROOF_STATUS.md` :
    - le théorème principal référencé est désormais
      `triple_valid_conditional_correctness` ;
    - les bridges externes sont explicitement marqués comme raffinements
      optionnels.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK ;
  - `opam exec --switch=5.4.1+options -- dune build` OK.

### 2026-03-07 — Renommage des théorèmes d’intégration

- Demande :
  - éviter d’exposer partout des noms hérités de type
    `oracle_conditional_correctness`.

- Décision :
  - renommage additif, pas cassant :
    - nouveaux noms lisibles ;
    - anciens noms conservés comme alias de compatibilité.

- Modifications :
  - `rocq/kernels/SafetyKernel.v`
    - nouveau nom :
      - `validation_conditional_correctness_modular`
  - `rocq/kernels/ObjectiveSafetyKernel.v`
    - nouveaux noms :
      - `validation_conditional_correctness_from_objectives`
      - `validation_conditional_correctness_with_supports`
  - `rocq/integration/ThreeLayerArchitecture.v`
    - nouveau nom :
      - `validation_conditional_correctness_three_layers`
  - `rocq/integration/EndToEndTheorem.v`
    - nouveau nom :
      - `end_to_end_validation_conditional_correctness`
  - mises à jour des usages dans :
    - `rocq/integration/ProgramLTLSpecBridge.v`
    - `rocq/integration/AdmissibilityNonVacuity.v`
    - `rocq/instances/DelayIntInstance.v`
  - `rocq/PROOF_STATUS.md` mis à jour pour expliquer que les noms
    `oracle_*` sont désormais seulement des alias de compatibilité.

- Vérifications :
  - recompilation Rocq complète à relancer après ce lot ;
  - `dune build` à relancer après ce lot.

## 2026-03-07 — Passe terminologique sur le papier mathématique

- Objectif :
  - supprimer l’ambiguïté persistante entre `obligation`, `clause` et `triple`
    dans `spec/rocq_oracle_model.tex`.

- Modifications :
  - remplacement systématique, dans le papier, de `obligation(s)` par :
    - `clause(s)` pour les objets sémantiques locaux générés depuis le produit ;
    - `relational Hoare triple(s)` ou `proof object(s)` pour les objets de
      validation ;
    - `verification condition(s)` uniquement au niveau Why3.
  - renommage du titre en `Safety Automata, Explicit Products, and Local Clauses
    for Kairos`.
  - renommage de la section en `Pseudo-Algorithmic Generation of Clauses and
    Triples`.
  - clarification explicite de la chaîne :
    `product -> clauses -> triples -> Why3 verification conditions`.

- Résultat :
  - le papier est maintenant cohérent avec le noyau Rocq triple-centric et ne
    laisse plus entendre que les clauses sont elles-mêmes les obligations
    externes.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` OK
  - PDF produit : `spec/rocq_oracle_model.pdf`

## 2026-03-07 — Découpage Rocq en 7 étapes lisibles

- Demande :
  - faire suivre au développement Rocq le découpage conceptuel :
    1. produit sémantique ;
    2. extraction de clauses ;
    3. construction de triples relationnels ;
    4. regroupement par transition ;
    5. validité des triples ;
    6. récupération de la validité sémantique des clauses ;
    7. réduction global-vers-local.

- Modifications :
  - ajout des façades de lecture :
    - `rocq/path/Step1SemanticProduct.v`
    - `rocq/path/Step2GeneratedClauses.v`
    - `rocq/path/Step3RelationalTriples.v`
    - `rocq/path/Step4TransitionBundles.v`
    - `rocq/path/Step5TripleValidity.v`
    - `rocq/path/Step6ClauseRecovery.v`
    - `rocq/path/Step7GlobalToLocal.v`
  - mise à jour de `rocq/MainProofPath.v` pour exposer explicitement ces
    sept étapes comme chemin de lecture privilégié.
  - mise à jour de `rocq/README.md` et `rocq/PROOF_STATUS.md` pour documenter
    ce parcours.

- Résultat :
  - la structure mathématique du noyau n’est pas changée ;
  - en revanche, la lecture du développement suit maintenant explicitement le
    découpage conceptuel fixé pendant l’audit.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- rocq makefile -R rocq '' rocq/*.v rocq/*/*.v -o rocq_build.mk` OK
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK
  - `opam exec --switch=5.4.1+options -- dune build` OK

## 2026-03-07 — Prédicat nommé de bonne formation du modèle Rocq

- Demande :
  - cesser de laisser la bonne formation du programme sous forme
    d’hypothèses structurelles dispersées ;
  - introduire un prédicat nommé regroupant ces conditions.

- Modifications :
  - ajout dans `rocq/KairosOracle.v` de :
    - `WellFormedProgramModel : Prop`
    - `current_model_well_formed : WellFormedProgramModel`
  - ajout des wrappers :
    - `triple_valid_conditional_correctness_under_wf`
    - `triple_valid_conditional_correctness_with_node_inv_under_wf`
  - exposition de `WellFormedProgramModel` dans
    `rocq/path/Step1SemanticProduct.v`
  - mise à jour de `rocq/MainProofPath.v` et
    `rocq/INTENDED_THEOREM_AUDIT.md` pour utiliser cette notion nommée.

- Résultat :
  - la bonne formation du modèle est maintenant visible comme un bloc
    conceptuel unique ;
  - le noyau reste prouvé comme avant, mais l’audit et le chemin principal de
    lecture peuvent désormais parler d’une hypothèse unique nommée.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK

## 2026-03-07 — Passe de proof engineering sur la chaîne principale Rocq

- Demande :
  - étendre la passe de proof engineering au-delà de `KairosOracle.v`,
    mais seulement sur la chaîne principale :
    `core -> kernels -> integration`,
    plus un nettoyage léger des points d’entrée et exemples.

- Modifications :
  - `rocq/core/AutomataCorrectnessCore.v`
    - exposition des trois grandes étapes du noyau avec alias mieux nommés ;
  - `rocq/integration/ThreeLayerFromCore.v`
    - facteur local `recover_falsified_clause_from_global_violation` ;
  - `rocq/integration/AutomataFinalCorrectness.v`
    - facteur local `validated_generated_clauses_hold` ;
  - `rocq/kernels/SafetyKernel.v`
    - facteur local `validated_generated_clause_holds` ;
  - `rocq/kernels/ObjectiveSafetyKernel.v`
    - facteurs locaux renommés en `...clauses...`
    - facteur local `objective_clauses_rule_out_bad_ticks` ;
  - `rocq/MainProofPath.v`, `rocq/KairosRefactorBlueprint.v`
    - commentaires de lecture clarifiés ;
  - `rocq/instances/DelayIntInstance.v`, `rocq/DelayIntExample.v`
    - commentaires de rôle clarifiés pour éviter d’y reconstruire la preuve
      principale.

- Résultat :
  - la chaîne principale Rocq reflète mieux les grandes étapes du raisonnement
    sans multiplier les façades artificielles ;
  - les modules dérivés réutilisent explicitement les étapes du noyau au lieu
    d’écraser leur sens sous des preuves compactes.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK
  - `opam exec --switch=5.4.1+options -- dune build` OK

## 2026-03-07 — Structuration “humaine” directement dans le noyau

- Demande :
  - faire ressortir les grandes étapes de raisonnement pour préparer un papier
    lisible, mais sans ajouter une façade Rocq artificielle dédiée.

- Modifications :
  - suppression de la couche `rocq/HumanProofStages.v`, jugée moins lisible
    qu’une structuration directe du noyau ;
  - suppression de `rocq/HUMAN_PROOF_OUTLINE.md` ;
  - `rocq/KairosOracle.v` marque maintenant directement les étapes importantes
    de la preuve par blocs de commentaires ;
  - adoption d’une hiérarchie plus explicite :
    - `Local Lemma` / `Local Fact` pour la plomberie interne ;
    - `Proposition` pour les résultats intermédiaires importants ;
    - `Theorem` pour les jalons globaux.

- Découpage retenu dans `KairosOracle.v` :
  1. progression du produit ;
  2. violation globale -> tick dangereux ;
  3. helper facts valides le long du run ;
  4. tick dangereux -> clause générée falsifiée ;
  5. tick dangereux -> triple NoBad applicable ;
  6. validité des triples -> correction conditionnelle globale.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` à relancer
    après suppression de la façade.

## 2026-03-07 — Passe de proof engineering sur `KairosOracle.v`

- Demande :
  - rendre la structure des preuves plus lisible et plus proche des étapes de
    raisonnement retenues pendant l’audit.

- Modifications :
  - ajout de `helper_context_holds_on_run` pour factoriser le contexte helper
    utilisé par `generation_coverage` et `triple_generation_coverage` ;
  - ajout de `generated_no_bad_triple_contradiction` pour isoler l’étape finale
    “triple NoBad valide + précondition vraie => contradiction” ;
  - simplification des preuves de :
    - `generation_coverage`
    - `triple_generation_coverage`
    - `triple_valid_conditional_correctness`
  - hiérarchie de visibilité stabilisée :
    - `Local Lemma` / `Local Fact` pour la plomberie ;
    - `Proposition` pour les résultats intermédiaires structurants ;
    - `Theorem` pour les jalons globaux.

- Résultat :
  - les dépendances sont plus lisibles dans le fichier lui-même ;
  - la preuve finale se lit davantage comme :
    1. violation globale ;
    2. tick dangereux ;
    3. triple NoBad applicable ;
    4. contradiction par validité du triple.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` OK

### 2026-03-07 — Noms de signatures: `VALIDATION_*` plutôt que `ORACLE_*`

- Demande :
  - poursuivre la simplification des noms exposés ;
  - réduire la présence du vocabulaire `oracle` dans les signatures et
    interfaces visibles.

- Décision :
  - renommage additif, sans casser les fichiers ni les usages existants ;
  - les noms historiques sont gardés comme alias de compatibilité.

- Modifications :
  - `rocq/obligations/OracleSig.v`
    - ajout de `VALIDATION_SIG` comme alias lisible de `ORACLE_SIG`.
  - `rocq/obligations/OracleSemSig.v`
    - ajout de `VALIDATION_SEM_SIG` comme alias lisible de `ORACLE_SEM_SIG`.
  - `rocq/interfaces/ExternalValidationAssumptions.v`
    - ajout de `VALIDATION_ASSUMPTIONS` ;
    - ajout de :
      - `MakeValidationAssumptionsFromOracleSem`
      - `MakeValidationAssumptionsFromTransitionTriples`
  - `rocq/KairosRefactorBlueprint.v`
    - expose maintenant `VALIDATION_SIG` et `VALIDATION_SEM_SIG` ;
  - `rocq/README.md` et `rocq/PROOF_STATUS.md`
    - expliquent que `VALIDATION_*` est le vocabulaire préféré ;
    - `ORACLE_*` n’est plus qu’un alias de compatibilité.

- Vérifications :
  - recompilation Rocq complète à relancer après ce lot ;
  - `dune build` à relancer après ce lot.

### 2026-03-07 — Fichiers façades `Validation*.v`

- Demande :
  - aller au bout de la simplification pour les lecteurs ;
  - ne plus dépendre uniquement de noms lisibles à l’intérieur de fichiers
    historiquement nommés `Oracle*`.

- Modifications :
  - commentaires de tête ajoutés dans :
    - `rocq/obligations/OracleSig.v`
    - `rocq/obligations/OracleSemSig.v`
    - `rocq/interfaces/ExternalValidationAssumptions.v`
    pour signaler explicitement qu’il s’agit de noms historiques.
  - ajout des fichiers façades :
    - `rocq/obligations/ValidationSig.v`
    - `rocq/obligations/ValidationSemSig.v`
    - `rocq/interfaces/ValidationAssumptions.v`
  - mise à jour de :
    - `rocq/README.md`
    - `rocq/PROOF_STATUS.md`
    pour pointer vers ces fichiers comme entrées de lecture préférées.

- Vérifications :
  - recompilation Rocq complète à relancer après ce lot ;
  - `dune build` à relancer après ce lot.

### 2026-03-07 — Refonte de la section de preuve du papier mathématique

- Demande :
  - mettre à jour `spec/rocq_oracle_model.tex` en intégrant les dernières
    modifications du noyau Rocq ;
  - détailler le théorème final et les résultats intermédiaires importants ;
  - relire la chaîne de preuve papier pour vérifier qu’il n’y a pas de trou
    logique après la mise à jour.

- Méthodologie :
  - repartir de la structure effective de `rocq/KairosOracle.v` ;
  - aligner la section de preuve du papier sur les jalons réellement stabilisés
    dans le noyau :
    1. hypothèses globales ;
    2. progression du produit ;
    3. violation globale vers tick dangereux ;
    4. faits helper init/propagation ;
    5. couverture par clause ;
    6. couverture par triple ;
    7. contradiction finale par validité du triple `NoBad`.
  - recompiler le PDF après modification ;
  - relire ensuite la preuve papier en continu pour vérifier que les résultats
    s’enchaînent bien sans réintroduire d’hypothèse implicite externe.

- Modifications :
  - `spec/rocq_oracle_model.tex`
    - réécriture complète de `Proof Structure` ;
    - suppression de la séparation ancienne entre hypothèses internes et
      “externes” dans le cœur du raisonnement ;
    - introduction explicite de `WellFormedProgramModel` et de l’hypothèse
      `GeneratedTripleValid` comme seules hypothèses globales du théorème cœur ;
    - ajout de preuves détaillées pour :
      - la progression du produit ;
      - la réduction d’une violation globale à un tick dangereux ;
      - l’établissement initial et la propagation des faits helper ;
      - la couverture clause-level ;
      - la couverture triple-level ;
      - le théorème final de correction conditionnelle ;
    - clarification du rôle respectif de `generation_coverage` et
      `triple_generation_coverage` ;
    - correction d’un usage invalide de l’environnement LaTeX `corollary`
      remplacé par `proposition`.

- Résultat :
  - le papier suit maintenant beaucoup plus fidèlement la structure de preuve
    réelle du noyau Rocq ;
  - la chaîne de raisonnement est présentée comme une suite de résultats
    intermédiaires mathématiquement motivés, plutôt que comme un simple résumé
    narratif ;
  - le noyau mathématique du papier ne parle plus d’un validateur externe, mais
    directement de validité des triples générés.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
    - OK ;
    - restent uniquement des warnings LaTeX mineurs de mise en page
      (`Overfull \\hbox`, flottants `h` transformés en `ht`).

### 2026-03-07 — Relecture critique approfondie du papier comme reviewer

- Demande :
  - relire le papier comme un reviewer expérimenté ;
  - vérifier qu’aucun résultat n’utilise de notion insuffisamment définie ;
  - vérifier que les preuves ne sautent pas d’étape de raisonnement importante ;
  - ajouter au besoin les résultats intermédiaires Rocq nécessaires pour rendre
    ces étapes visibles et exportables vers le papier.

- Problèmes conceptuels détectés :
  - incohérence entre la définition de `TickCtx` et une redéfinition ultérieure
    de `ctx(u,k)` qui y faisait entrer les états automates `A/G`, alors que la
    formalisation Rocq sépare explicitement `StepCtx` (contexte programme) et
    état du produit ;
  - absence de définition formelle explicite des triples de Hoare relationnels
    et de leur validité dans le papier, alors qu’ils sont maintenant les vrais
    objets de validation du noyau ;
  - absence de définition explicite des relations `Generated` et
    `GeneratedTriple`, pourtant utilisées ensuite dans les énoncés ;
  - léger trou de raisonnement dans les preuves papier : pour utiliser la
    validité d’un triple, il faut aussi un lemme reliant un pas réalisé à la
    relation de transition `TransRel_t`.

- Modifications Rocq :
  - `rocq/KairosOracle.v`
    - promotion en résultats publics de :
      - `ctx_at_matches_realized_ps`
      - `transition_rel_of_realized_step`
    afin que la lecture “papier” puisse citer explicitement ces étapes
    intermédiaires au lieu de reposer sur de la plomberie locale implicite.

- Modifications papier :
  - `spec/rocq_oracle_model.tex`
    - correction de la définition de `ctx(u,k)` pour qu’elle coïncide avec le
      contexte local de programme, les états automates étant récupérés via le
      run du produit ;
    - redéfinition de `Match` comme matching minimal de la partie programme,
      fidèle à `ctx_matches_ps` ;
    - réécriture de l’exemple `delay_int` pour faire apparaître la vraie place
      de la contradiction : dans le triple `NoBad`, via la relation de
      transition et les faits helper, et non dans la clause brute seule ;
    - ajout de définitions formelles pour :
      - `InitCtx`,
      - `TransRel_t`,
      - les triples de Hoare relationnels,
      - leur validité,
      - les cinq formes canoniques de triples générés,
      - `GeneratedBy`, `Generated`, `GeneratedTriple` ;
    - ajout, dans la structure de preuve, d’un résultat intermédiaire explicite
      affirmant qu’un pas réalisé induit bien la relation de transition utilisée
      par les triples.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2`
    - OK ;
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
    - OK ;
  - après cette passe, les problèmes restants identifiés dans le PDF sont
    typographiques (principalement des `Overfull \\hbox`), pas des trous
    conceptuels du noyau de preuve.

### 2026-03-08 — Rehaussement scientifique de l’introduction

- Demande :
  - améliorer nettement l’introduction ;
  - situer Kairos dans le cadre du synchrone ;
  - expliciter le lien avec les techniques de vérification existantes ;
  - mettre en avant la difficulté particulière des programmes à domaines non
    bornés ;
  - renforcer l’appui bibliographique.

- Modifications :
  - `spec/rocq_oracle_model.tex`
    - réécriture substantielle de l’introduction ;
    - positionnement explicite par rapport :
      - aux cadres synchrones / contrats / observateurs
        (`lustre-pvs`, `AGREE`, `Kind 2`, `CoCoSpec`) ;
      - aux approches par compilation de propriétés temporelles en objets de
        preuve locaux (`Aorai`, `CaFE`) ;
    - ajout d’un paragraphe dédié à la difficulté des domaines non bornés,
      pour expliquer pourquoi le cadre n’est pas celui d’un simple model
      checking explicite ;
    - clarification de la contribution propre de Kairos :
      produit explicite `program × A × G`, extraction de clauses sémantiques,
      assemblage en triples de Hoare relationnels, puis validation backend ;
    - nettoyage d’une répétition résiduelle dans le paragraphe `Copilot` de la
      section `Related Work`.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
    - OK ;
    - restent uniquement des warnings LaTeX de mise en page (`Overfull \\hbox`).

### 2026-03-08 — Passe critique type POPL/PLDI sur introduction et related work

- Demande :
  - relire le papier comme un reviewer POPL/PLDI exigeant ;
  - hausser le niveau scientifique de l’introduction ;
  - mieux situer Kairos par rapport au synchrone, aux approches déductives
    sur propriétés temporelles, et au cas particulier des domaines non bornés.

- Modifications :
  - `spec/POPL_PLDI_REVIEW_2026-03-08.md`
    - note de review structurée, avec critiques sur :
      - abstract trop descriptif,
      - introduction insuffisamment positionnée,
      - related work trop énumératif,
      - nouveauté encore insuffisamment articulée autour du cas non borné ;
  - `spec/rocq_oracle_model.tex`
    - réécriture de l’abstract dans un style plus théorème/contribution ;
    - introduction recentrée sur :
      - la vérification synchrone,
      - la réduction de propriétés temporelles globales à des objets de preuve
        locaux,
      - la difficulté du cas non borné,
      - la contribution spécifique de Kairos ;
    - related work renforcé sur deux axes :
      - compilation déductive de propriétés temporelles vers objets de preuve ;
      - synchrones / contrats / assume-guarantee ;
    - clarification de la nouveauté exacte :
      - produit explicite `program × A × G`,
      - clauses et triples comme point de jonction entre couche temporelle
        finie et couche déductive sur programme non borné ;
    - resserrement du paragraphe `Position of Kairos` pour en faire une vraie
      synthèse de positionnement, et non une simple liste de différences.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
    - OK ;
    - PDF produit : `spec/rocq_oracle_model.pdf` ;
    - warnings résiduels limités à de la mise en page (`Overfull \\hbox`).

### 2026-03-08 — Seconde passe reviewer POPL/PLDI (claims, gap, conclusion)

- Demande :
  - relire à nouveau le papier avec un niveau d’exigence de reviewer POPL/PLDI ;
  - améliorer encore la rigueur de positionnement scientifique ;
  - rendre plus explicite le gap exact par rapport aux travaux proches ;
  - calibrer plus proprement les claims et la conclusion.

- Diagnostic retenu :
  - l’introduction était déjà meilleure, mais restait encore un peu
    ``descriptive'' ;
  - le gap scientifique n’était pas assez formulé comme un problème de jonction
    entre automates finis et raisonnement déductif sur programme à domaines non
    bornés ;
  - `Related Work` restait encore trop proche d’une liste d’outils, avec une
    comparaison pas assez organisée selon des axes conceptuels ;
  - la conclusion restait trop proche d’un résumé documentaire, plutôt que de
    rappeler nettement la portée théorique et les limites de la contribution.

- Modifications :
  - `spec/rocq_oracle_model.tex`
    - abstract durci sur :
      - la présence explicite d’hypothèses de bonne formation ;
      - la séparation entre cœur mathématique et raffinements backend ;
    - introduction enrichie avec :
      - une formulation plus explicite de la question méthodologique centrale ;
      - un paragraphe sur le vrai risque scientifique : perdre soit la
        temporalité globale, soit le programme non borné ;
      - un paragraphe `What is non-standard here` pour nommer clairement la
        nouveauté ;
    - `Related Work` renforcé avec :
      - un cadrage en deux axes de comparaison (`what is proved` / `how proof
        is mediated`) ;
      - une meilleure différenciation avec Aorai, AGREE, Kind 2/CoCoSpec,
        Lustre/PVS ;
      - un paragraphe de synthèse finale qui explicite la niche exacte de
        Kairos ;
    - conclusion réécrite pour :
      - rappeler la leçon méthodologique centrale ;
      - expliciter proprement la portée des résultats ;
      - identifier des directions de recherche restantes sans survendre.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
    - OK ;
    - PDF produit : `spec/rocq_oracle_model.pdf` ;
    - warnings résiduels toujours limités à de la mise en page.

### 2026-03-08 — Recentrage abstract/introduction sur safety et triples de Hoare

- Demande :
  - éviter d’ouvrir trop tôt sur les automates ;
  - présenter d’abord la propriété de safety et les triplets de Hoare sur les
    ticks ;
  - introduire seulement ensuite les automates de sûreté comme compilation
    standard des spécifications, avec référence ;
  - reléguer Why3 au niveau backend, également avec référence.

- Modifications :
  - `spec/rocq_oracle_model.tex`
    - titre changé vers `Conditional Safety, Explicit Products, and Relational
      Hoare Triples for Kairos` ;
    - abstract recentré sur :
      - propriété de safety conditionnelle,
      - triples de Hoare relationnels,
      - séparation cœur mathématique / backend ;
    - introduction réécrite pour :
      - parler d’abord de propriétés de safety sur traces et de raisonnement
        local sur ticks ;
      - introduire ensuite la compilation vers automates de sûreté comme un
        choix mathématique standard adapté au fragment safety de LTL utilisé par
        l’outil ;
      - introduire Why3 seulement dans la section backend ;
    - ajout des références :
      - `kupferman-vardi-safety`
      - `gastin-oddoux`
      - `why3`

- Vérifications :
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
    - OK ;
    - PDF produit : `spec/rocq_oracle_model.pdf` ;
    - warnings résiduels inchangés et purement typographiques.

### 2026-03-08 — Refonte pédagogique des exemples et des automates

- Demande :
  - ne garder qu’un seul exemple central ;
  - le rendre plus pertinent, avec hypothèse d’entrée non triviale ;
  - présenter systématiquement programme, automates, pas dangereux, clause et
    triple de manière pédagogique ;
  - améliorer la lisibilité graphique des automates.

- Modifications :
  - `spec/rocq_oracle_model.tex`
    - suppression du second exemple `toggle` du corps mathématique ;
    - promotion de `delay_int` comme unique exemple fil rouge ;
    - enrichissement de la spécification avec une hypothèse d’entrée
      monotone non décroissante :
      - `A := X G(x >= prev(x))`
      - `G := X G(y = prev(x))`
    - ajout d’un automate d’hypothèse dédié pour cet exemple ;
    - réécriture de la présentation de l’exemple détaillé pour suivre le fil :
      - état produit source,
      - arête d’hypothèse,
      - arête de garantie,
      - clause générée,
      - triple `NoBad`,
      - contradiction ;
    - amélioration des figures TikZ avec styles dédiés (`kairosstate`,
      `kairoslabel`) et espacements plus grands pour éviter les recouvrements ;
    - mise à jour du sous-graphe produit de l’exemple avec les états
      `Asm_0`, `Asm_ok`, `Asm_bad`, `Mon_0`, `Mon_1`, `Mon_bad`.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
    - OK ;
    - PDF produit : `spec/rocq_oracle_model.pdf` ;
    - plus de second exemple dans le corps mathématique ; warnings résiduels
      purement typographiques.

### 2026-03-08 — Remplacement du fil rouge par resettable_delay

- Demande :
  - abandonner `delay_int` comme exemple central ;
  - choisir un exemple où l’hypothèse d’entrée intervient réellement dans la preuve, sans être une simple conséquence du décalage ;
  - présenter de manière pédagogique programme, automates, sous-graphe produit, clauses et triples associés.

- Modifications :
  - `spec/rocq_oracle_model.tex`
    - remplacement du fil rouge `delay_int` par `resettable_delay` ;
    - programme à deux modes (`Init`, `Run`) avec entrée `(reset, x)`, mémoire entière `m` et sortie `y` ;
    - hypothèse d’entrée : `G(ResetOk)` avec `ResetOk := (not reset or x = 0)` ;
    - garantie découpée en trois branches nommées :
      - `GRst` pour les ticks de reset ;
      - `GAfterRst` pour le premier tick non-reset après un reset ;
      - `GDelay` pour le régime de délai ordinaire ;
    - invariant utilisateur agrégé sur `Run` : mémoire égale à `0` après reset, sinon à `prev(x)` ;
    - réécriture complète des figures d’automates et du sous-graphe produit pour montrer deux familles de pas dangereux :
      - une famille exclue par le support d’hypothèse ;
      - une famille exclue par le support invariant utilisateur ;
    - réécriture de l’exemple détaillé pour faire apparaître explicitement :
      - le pas dangereux abstrait ;
      - la clause générée ;
      - le triple `NoBad` correspondant ;
      - la contradiction locale obtenue.

- Vérifications :
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
    - OK ;
    - PDF produit : `spec/rocq_oracle_model.pdf` ;
    - warnings résiduels purement typographiques.

### 2026-03-08 — Instanciation Kairos concrete de `resettable_delay`

- Demande :
  - ecrire le nouvel exemple central en vrai Kairos ;
  - le faire passer dans le pipeline pour obtenir des artefacts concrets ;
  - reutiliser ces artefacts dans la section technique du papier.

- Modifications :
  - `tests/ok/inputs/resettable_delay.kairos`
    - ajout du programme source Kairos avec :
      - entrees `reset`, `x` ;
      - hypothese `G((reset = 0 or reset = 1) and (reset = 1 => x = 0))` ;
      - garanties `reset` / `post-reset` / `delay ordinaire` ;
      - invariant utilisateur piecewise sur `m`.
  - `spec/generated/resettable_delay/README.md`
    - note de reproduction locale avec les commandes et le resume des sorties.
  - `spec/rocq_oracle_model.tex`
    - ajout d'une sous-section technique concrete sur `resettable_delay` dans la
      partie implementation/backend.
  - `objectif_methodologie.md`
    - mise a jour de l'objectif courant et de la methodologie.

- Artefacts generes :
  - `spec/generated/resettable_delay/automata.txt`
  - `spec/generated/resettable_delay/product.txt`
  - `spec/generated/resettable_delay/obligations.txt`
  - `spec/generated/resettable_delay/resettable_delay.obc+`
  - `spec/generated/resettable_delay/resettable_delay.mlw`
  - `spec/generated/resettable_delay/resettable_delay_vc.txt`

- Resultats observes :
  - l'extraction complete reussit ;
  - automates residuels :
    - hypothese : `A0`, `A1` ;
    - garantie : `G0`, `G1`, `G2` ;
  - produit atteignable : 5 etats ;
  - clauses generees : 34
    - safety : 13 ;
    - helper : 21 ;
    - init goal : 1 ;
    - propagation : 20 ;
    - user invariant : 6 ;
    - automaton support : 14.

- Validation backend :
  - une tentative Why3/Z3 bornee (2 secondes par goal) sur le fichier `.mlw`
    produit des timeouts sur les premiers goals (`step'vc`,
    `coherency_goal_1`) ;
  - conclusion : l'exemple est deja exploitable comme temoin d'architecture et
    de generation d'artefacts, mais pas encore comme benchmark completement
    decharge automatiquement sous ce budget.

## 2026-03-08 — Unification du binaire V2 pour les artefacts concrets

- Objectif :
  - eliminer l'ambiguite entre `main.exe` et `main_v2.exe` pour les extractions
    utilisees dans le papier et la documentation ;
  - garantir que tous les artefacts de `resettable_delay` passent par le meme
    frontend V2 que celui conforme a la formalisation et a l'architecture
    courante.

- Constat :
  - les dumps `--dump-automata`, `--dump-product` et
    `--dump-obligations-map` etaient deja routes vers `Pipeline_v2_indep`
    depuis `cli.ml`, mais seulement exposes par `main.exe` ;
  - `main_v2.exe` ne portait pas encore ces modes diagnostics, ce qui nuisait a
    la lisibilite de la chaine de generation.

- Modifications :
  - `bin/cli/cli_v2.ml`
    - ajout des options V2 :
      - `--dump-dot`
      - `--dump-dot-short`
      - `--dump-automata`
      - `--dump-product`
      - `--dump-obligations-map`
      - `--dump-prune-reasons`
    - routage explicite via
      `Engine_service.instrumentation_pass ~engine:Engine_service.V2`.
  - `spec/generated/resettable_delay/README.md`
    - commandes de reproduction mises a jour pour n'utiliser que
      `_build/default/bin/cli/main_v2.exe`.

- Validation :
  - `opam exec --switch=5.4.1+options -- dune build` : OK ;
  - `main_v2.exe --help` expose maintenant bien les dumps diagnostics V2 ;
  - regeneration complete de `resettable_delay` avec `main_v2.exe` seulement :
    - `automata.txt`
    - `product.txt`
    - `obligations.txt`
    - `resettable_delay.obc+`
    - `resettable_delay.mlw`
    - `resettable_delay_vc.txt`
  - les artefacts canoniques du repertoire `spec/generated/resettable_delay/`
    ont ete remplaces par les sorties issues du binaire V2 unique.

## 2026-03-08 — Backend Why3 de `resettable_delay`

- Objectif :
  - faire passer l'exemple `resettable_delay` jusqu'au backend Why3 a partir du
    binaire V2 canonique.

- Diagnostic :
  - les premiers sous-buts `step'vc` etaient deja prouvables apres
    simplification Why3 (`simplify_formula`, `eliminate_if_term`,
    `remove_unused`, `split_vc`) ;
  - le blocage principal restant venait d'un goal de coherence initiale
    universellement faux :
    - `forall vars, reset, x. vars.__aut_state = Aut0`
  - ce goal etait produit par `add_initial_automaton_support_goal`, alors que
    la couche Why3 concrete quantifie les goals de coherence sur un pre-etat
    arbitraire et ne dispose pas encore d'une vraie semantique
    d'initialisation.

- Tentative abandonnee :
  - normaliser trop tot les variables `{0,1}` comme des booleens dans la
    generation des automates ;
  - cette piste modifiait la semantique de l'exemple (des variables entieres
    comme `x` et `y` etaient reconnues a tort comme bool-like) ;
  - elle a ete revertie integralement.

- Correction retenue :
  - `lib_v2/runtime/middle_end/instrumentation/instrumentation.ml`
    - suppression de l'emission de l'`initial automaton support goal` tant
      qu'il n'est pas encode sous une forme initiale semantiquement correcte
      dans les VCs Why3.

- Resultat :
  - regeneration correcte de `resettable_delay_v2.mlw` avec `main_v2.exe` ;
  - les clauses generees reviennent a une repartition coherente :
    - `safety = 3`
    - `helper = 19`
    - `initial_goal = 1`
    - `user_invariant = 6`
    - `automaton_support = 12`
  - les sous-buts `step'vc` se dechargent avec :
    - `why3 prove -a simplify_formula -a eliminate_if_term -a remove_unused -a split_vc -P z3 -t 30`
  - le faux `coherency_goal_1` n'est plus genere ;
  - la commande Why3 complete termine avec succes (`EXIT=0`) sur
    `spec/generated/resettable_delay/resettable_delay.mlw`.

## 2026-03-08 — Exemple Kairos complet dans le papier

- `spec/rocq_oracle_model.tex`
  - remplacement de l’extrait partiel de `resettable_delay` par le nœud Kairos complet afin de montrer explicitement la syntaxe du langage source.
## 2026-03-08 — Réintroduction saine de l'initialisation du support automate

- Contexte : pour faire passer `resettable_delay`, l'émission du but initial de support automate avait été désactivée car la traduction Why3 précédente produisait un but universellement quantifié faux (`forall vars. __aut_state = Aut0`).
- Diagnostic : le problème ne venait pas du besoin de preuve lui-même, mais du fait que les `coherency_goals` init étaient compilés comme buts universels nus, sans garde initiale.
- Correction retenue :
  - réémission du goal init de support automate dans [`lib_v2/runtime/middle_end/instrumentation/instrumentation.ml`](/Users/fredericdabrowski/Repos/kairos/lib_v2/runtime/middle_end/instrumentation/instrumentation.ml) comme fait `FImp(FTrue, __aut_state = Aut0)` ;
  - modification de [`lib_v2/runtime/backend/emit.ml`](/Users/fredericdabrowski/Repos/kairos/lib_v2/runtime/backend/emit.ml) pour compiler les init goals sous une garde initiale explicite `st = Init /\ __aut_state = Aut0`.
- Résultat :
  - le but initial réapparaît dans le Why3 généré sous la forme saine
    `((vars.st = Init) /\\ (vars.__aut_state = Aut0)) -> (vars.__aut_state = Aut0)` ;
  - Why3/Z3 le prouve ;
  - `resettable_delay` reste entièrement validé.
- Conclusion : le backend re-matérialise maintenant explicitement l'`InitialGoal` de support automate utilisé par le noyau Rocq, sans retomber sur le bug d'universalisation précédente.

## 2026-03-08 — Généralisation Rocq aux mémoires initiales admissibles

- Objectif :
  - réaligner le noyau Rocq avec l’intuition Kairos selon laquelle la mémoire
    initiale n’est pas une valeur totalement connue, mais appartient à une
    classe d’états initiaux admissibles.

- Refactoring du noyau :
  - [`rocq/KairosOracle.v`](/Users/fredericdabrowski/Repos/kairos/rocq/KairosOracle.v)
    - introduction de `prog_init_mem_ok : Mem -> Prop` dans `ProgramSemantics` ;
    - ajout des variantes paramétrées par `m0` :
      `cfg_at_from`, `step_at_from`, `out_at_from`, `run_trace_from`,
      `ctx_at_from`, `run_product_state_from` ;
    - reformulation des clauses, triples et théorèmes principaux sur tout
      `m0` admissible ;
    - conservation d’alias spécialisés sur `init_mem` pour compatibilité.

- Réparations induites :
  - [`rocq/DelayIntExample.v`](/Users/fredericdabrowski/Repos/kairos/rocq/DelayIntExample.v)
    - réécriture des preuves trop dépendantes de l’ancienne présentation de
      `cfg_at`, `out_at` et `run_trace` ;
    - stabilisation sur `cfg_at_from` / `run_trace_from`.
  - [`rocq/instances/DelayIntInstance.v`](/Users/fredericdabrowski/Repos/kairos/rocq/instances/DelayIntInstance.v)
    - réalignement des preuves de cohérence de contexte sur `ctx_at_from` et
      `run_trace_from`.

- Alignement documentaire :
  - [`rocq/INTENDED_THEOREM_AUDIT.md`](/Users/fredericdabrowski/Repos/kairos/rocq/INTENDED_THEOREM_AUDIT.md)
    explicite maintenant que le théorème final quantifie sur une mémoire
    initiale admissible.
  - [`spec/rocq_oracle_model.tex`](/Users/fredericdabrowski/Repos/kairos/spec/rocq_oracle_model.tex)
    introduit `InitMem`, l’idée de contexte initial partiellement contraint,
    et reformule `InitCtx`, `TransRel`, puis le théorème final en conséquence.

- Validation :
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` : OK.
