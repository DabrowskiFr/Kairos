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
