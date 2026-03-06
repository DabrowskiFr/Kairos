# Objectif et methodologie

## Objectif courant
Fournir une instanciation Coq explicite du programme `delay_int` qui montre formellement:
- la sortie de flux `y = (0, u0, u1, ...)`,
- la relation memoire attendue apres initialisation (memoire = entree precedente).

## Methodologie
1. Instancier le modele generique `KairosOracleModel` avec:
   - etats de controle `SInit/SRun`,
   - transitions `TInit/TRun`,
   - memoire `nat`, entree/sortie `nat`.
2. Prouver des lemmes de dynamique locale (`cfg_at_succ`, `out_at_0`, `out_at_succ`).
3. Deriver un theoreme combine `delay_end_to_end`.
4. Compiler avec `coqc rocq/DelayIntExample.v` pour valider la preuve.

## Suite prevue
- Ajouter une instanciation complete des automates A/G et du produit avec preuves `avoids_bad_*`.
- Relier explicitement cette instanciation a la version "oracle conditionnelle".

## Objectif courant (mise a jour 2026-03-06)
Integrer l'architecture modulaire Rocq dans la base existante pour relier explicitement:
- admissibilite d'entree (automate A),
- correction du shift abstrait FO,
- theoreme de transfert d'un tick sous hypothese `avoids_bad_A`.

## Methodologie (mise a jour)
1. Exprimer les interfaces modulaires (`PROGRAM_SEM_SIG`, `SAFETY_SIG`, `HISTORY_LOGIC_SIG`, `INPUT_OK_LINK_SIG`).
2. Encapsuler les objets concrets Kairos dans un `Module Type` d'instance.
3. Instancier le foncteur de correction via un bridge (`KairosModularBridge`).
4. Prouver un theoreme pont vers la formulation concrete de `KairosOracleModel`.
5. Valider par compilation Rocq des fichiers modulaires.

## Suite prevue
- Remplacer l'engine d'obligations minimal du bridge par un raccord complet avec `GeneratedBy`/oracle.
- Migrer progressivement les theoremes principaux vers ce socle fonctoriel.

## Objectif courant (mise a jour 2026-03-06 - refactor applicatif)
Transformer la formalisation Rocq en contrat d'architecture pour guider le refactoring de l'application:
- interfaces stables par couche,
- preuves de correction locales,
- preuves de refinement entre implementation concrete et abstraction.

## Methodologie (mise a jour)
1. Definir les signatures modulaires par couche (core, monitor, logique, obligations, oracle, refinement).
2. Isoler un noyau de preuve minimal (`MakeShiftKernel`) utilise comme patron.
3. Faire converger les modules existants (`KairosOracle`, bridge) vers ces signatures.
4. Migrer ensuite les preuves end-to-end en reutilisant les kernels.

## Etat d'avancement (mise a jour 2026-03-06)
- Fait:
  - arborescence cible materialisee en fichiers Rocq,
  - bridge `KairosModularIntegration` raccorde a `GeneratedBy` reel (plus de stub trivial),
  - kernel surete modulaire (`MakeSafetyKernel`) et theoremes d'integration (`integration/EndToEndTheorem.v`),
  - couche de raffinement (`refinement/RefinementSig.v`, `refinement/ShiftRefinement.v`).
- Reste a faire:
  - instancier completement les nouveaux kernels avec une instance concrete (ex. `delay_int`) jusqu'au theoreme final fully instantiated,
  - relier explicitement les preuves de raffinement aux transformations concretes de l'implementation.

## Architecture cible stabilisee (3 couches)
1. Couche Programme (abstraite):
   - semantique reactive (`step`, `cfg_at`, `ctx_at`, `run_trace`), proprietes `AvoidA`/`AvoidG`.
2. Couche Noyau Kairos:
   - generation d'obligations et preuve de couverture locale des violations.
3. Couche Validation des obligations (abstraite):
   - validation avec `soundness`/`completeness` + lien pointwise vers la semantique (`ObligationValid_pointwise`).

Reference implementation Rocq:
- `rocq/integration/ThreeLayerArchitecture.v`.

## Liens critiques fermes (mise a jour 2026-03-06)
- Validation:
  - contrat enrichi `ORACLE_SEM_SIG` (avec validite pointwise) dans `rocq/obligations/OracleSemSig.v`.
- Semantique programme:
  - lois reactives explicites (`ctx_input_is_stream`, `cfg_ctx_coherent`, `trace_ctx_coherent`) dans `rocq/core/CoreReactiveLaws.v`.
- Unification:
  - `rocq/KairosRefactorBlueprint.v` aligne les signatures canoniques par aliases.
- Instance concrete:
  - `rocq/instances/DelayIntInstance.v` instancie completement la chaine 3 couches.

## Extension specification LTL (mise a jour)
- Formules LTL abstraites:
  - `rocq/logic/LTLPredicate.v` (`Formula`, `sat`).
- Lien automate <-> formule:
  - `rocq/monitor/MonitorLTLLink.v` (`avoids_bad <-> sat phi`).
- Lien correction programme <-> spec LTL:
  - `rocq/integration/ProgramLTLSpecBridge.v`:
    - si `AvoidA` implique `AvoidG` (preuve de correction),
    - et si `AvoidG` caracterise `phiG`,
    - alors le programme satisfait `phiG` sous `AvoidA`.

## Extensions de raccord abstrait (mise a jour)
- Compilation de contrats:
  - `rocq/contracts/ContractCompilerSig.v` (contrats source -> formules/automates via lois de correction).
- Validation graduee:
  - retiree du coeur pour conserver une formalisation centree sur `ObligationValid`.
- Non-vacuite:
  - `rocq/integration/AdmissibilityNonVacuity.v` (temoin admissible et existence d'une trace satisfaisant la garantie).

## Taxonomie des obligations (mise a jour)
- Separation explicite des obligations:
  1. `ObjectiveNoBad` (necessaires a la correction),
  2. `SupportAutomaton`,
  3. `SupportUserInvariant`.
- Fichiers:
  - `rocq/obligations/ObligationTaxonomySig.v`,
  - `rocq/obligations/ObligationStratifiedSig.v`.
- Ordre logique de traitement formalise:
  - objectif -> support automate -> support utilisateur.

## Couverture objectif renforcee (mise a jour)
- Noyau ajoute:
  - `rocq/kernels/ObjectiveSafetyKernel.v`.
- Contrat cle:
  - `objective_coverage_if_not_avoidG` :
    en cas de violation de garantie, on extrait explicitement une obligation
    de role `ObjectiveNoBad`.
- Theoreme derive:
  - `oracle_conditional_correctness_from_objectives` :
    la correction est obtenue en s'appuyant uniquement sur les obligations
    objectif valides.

## Convention de vocabulaire (mise a jour)
- La couche 3 est desormais nommee `VALIDATION_LAYER_SIG`.
- Le coeur de la formalisation ne fait plus reference a un solveur explicite:
  il raisonne uniquement en termes de validite abstraite des obligations.

## Pont implementation -> validite (mise a jour)
- Fichier:
  - `rocq/obligations/ImplementationValidatorBridge.v`.
- Contrat:
  - un validateur concret `Validator : Obligation -> bool`,
  - preuve de correction semantique (`true -> ObligationValid`),
  - completion sur les obligations generees,
  - passage automatique vers `ORACLE_SEM_SIG`.

## Pont Hoare + outil externe (mise a jour)
- Fichier:
  - `rocq/obligations/HoareExternalBridge.v`.
- Chaine cible:
  - `Obligation` -> `HoareTriple` (derive du coeur),
  - outil externe verifie le triplet,
  - sous hypothese `check_sound`, on recupere `ObligationValid`,
  - adaptation automatique vers `ORACLE_SEM_SIG`.

## Support non bloquant (mise a jour)
- Noyau:
  - `rocq/kernels/SupportNonBlockingKernel.v`.
- Theoreme:
  - `correction_preserved_if_oracles_agree_on_objectives` :
    les differences d'oracle sur les obligations de support n'impactent pas
    la correction, tant que l'accord sur les obligations objectif est conserve.

## Suite immediate
1. Remplacer dans `DelayIntInstance` le noyau/simulateur minimal par un raccord direct a la generation d'obligations reelle (`GeneratedBy`) et a l'oracle reel.
2. Reproduire la meme instanciation pour un second exemple non-trivial afin de valider la generalite du patron de refactor.

## Objectif documentaire (2026-03-06)
Mettre le document mathematique Rocq au niveau "guide de refactoring":
- derouler la chaine de correction etape par etape,
- fournir a chaque etape un exemple `delay_int` et un exemple `toggle`,
- privilegier des representations graphiques d'automates pour l'alignement
  entre formalisation et implementation.

### Methode appliquee
1. Ajouter une section transversale "Lecture par etapes" avant le developpement detaille.
2. Garder les definitions formelles existantes, mais ajouter des exemples couples
   `delay_int`/`toggle` pour chaque bloc de concept.
3. Recompiler le PDF et verifier l'absence d'erreur LaTeX bloquante.

## Objectif refactoring implementation v2 (2026-03-06)
Construire une nouvelle architecture implementation dans `lib_v2/`:
- alignement sur la decomposition Rocq,
- executable separe `kairos_v2`,
- reutilisation controlee des composants externes existants via adaptateurs.

### Methode active
1. Initialiser les interfaces abstraites dans `lib_v2/interfaces`.
2. Ajouter un pipeline v2 minimal (`lib_v2/pipeline/V2_pipeline`).
3. Raccorder v2 aux composants externes via `lib_v2/adapters/v2_native_external_bridge`.
4. Introduire un binaire dedie `kairos_v2` puis basculer `kairos` en v2 par defaut.

## Objectif courant (2026-03-06 - alignement verification v2)
Rendre explicite dans l'implementation v2 la correspondance avec la taxonomie Rocq des obligations:
- familles d'obligations identifiees et comptees sur l'OBC augmente verifie,
- trace visible dans les sorties pipeline (meta + obligations map),
- generation concrete conservee depuis la v1 quand elle realise deja la specification Rocq.

### Methodologie active
1. Definir une taxonomie implementation des obligations basee sur la provenance des formules.
2. Classifier toutes les obligations du programme OBC augmente (requires/ensures/goals de noeud).
3. Injecter cette classification dans la sortie v2:
   - `stage_meta`,
   - `obligations_map_text`.
4. Verifier compilation et execution des passes v2 sans regression.

## Objectif courant (2026-03-06 - unification de l'arborescence v2)
Supprimer le repertoire `lib/` de premier niveau et centraliser les bibliotheques
dans `lib_v2/` pour une structure explicitement v2.

### Methodologie active
1. Deplacer le contenu de `lib/` vers `lib_v2/runtime/`.
2. Conserver `obcwhy3_lib` pour le runtime historique et introduire des bibliotheques
   v2 par couche (`kairos_v2_*`) pour aligner le build sur la decomposition Rocq.
3. Mettre a jour la racine `dune` pour ne plus declarer `lib` dans les dossiers actifs.
4. Recompiler et executer les commandes smoke CLI v2.
5. Supprimer/neutraliser les entrees legacy (`runner`, `Pipeline.run*` et passes legacy).
