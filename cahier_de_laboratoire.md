# Cahier de laboratoire

## 2026-03-13

### Tentative 1 (enrichissement visuel du document IR sur `delay_int`)
- Objectif:
  - produire une version beaucoup plus detaillee du document sur les
    obligations IR;
  - ajouter des supports visuels exploitables dans le Markdown et dans le PDF;
  - montrer, pour `delay_int`, ce qui est genere a chaque etape du pipeline.
- Demarche suivie:
  - relecture du document source
    `docs/ir_obligations_etude_delay_int_2026-03-13.md`;
  - reutilisation des artefacts deja extraits pour `delay_int`:
    - produit explicite;
    - Why genere;
    - graphe DOT existant du programme/produit;
  - ajout de trois vues graphiques nouvelles en Graphviz:
    - pipeline des artefacts de preuve;
    - carte clauses-transitions;
    - vue temporelle de `pre(x,1)` et de `__pre_k1_x`;
  - reorganisation du document pour rendre explicite:
    - la progression source -> OBC -> produit -> clauses -> clauses
      relationnelles -> Why;
    - le role de chaque famille de clauses;
    - l'exemple `delay_int` etape par etape;
    - un tableau de synthese transition -> obligations.
- Resultat:
  - succes;
  - le document a ete fortement detaille et structure;
  - les figures SVG suivantes ont ete ajoutees:
    - `docs/assets/delay_int_pipeline.svg`;
    - `docs/assets/delay_int_clause_map.svg`;
    - `docs/assets/delay_int_temporal_view.svg`;
  - le PDF associe a ete regenere:
    - `docs/ir_obligations_etude_delay_int_2026-03-13.pdf`.
- Realisations:
  - nouveaux fichiers source Graphviz:
    - `docs/assets/delay_int_pipeline.dot`;
    - `docs/assets/delay_int_clause_map.dot`;
    - `docs/assets/delay_int_temporal_view.dot`;
  - regeneration des SVG via `dot`;
  - regeneration du PDF via `pandoc` + `xelatex`.
- Point architectural consigne dans le document:
  - `product_steps` et `generated_clauses` restent des artefacts de
    construction;
  - `relational_generated_clauses` est le bon chemin cible pour la preuve;
  - `pre(x,k)` doit etre visible comme variable symbolique avant Why sur ce
    chemin.

### Tentative 2 (renforcement pedagogique du document IR)
- Objectif:
  - rendre le document plus pedagogique pour un lecteur qui ne connait pas
    encore le pipeline;
  - mieux faire voir les types d'obligation et leur reduction successive.
- Demarche suivie:
  - ajout d'une legende rapide des objets manipules;
  - ajout d'une typologie des obligations (`INIT`, `SOURCE SUMMARY`,
    `PROPAGATION`, `SAFETY`, `TICK SUMMARY EXPORT`);
  - ajout d'une section anti-confusions;
  - ajout d'une vue "un tick, une obligation locale" pour `delay_int`;
  - ajout d'une table de reduction complete:
    - produit explicite;
    - clause brute;
    - clause relationnelle;
    - forme Why observable;
  - ajout d'une carte de lecture du Why et d'une vue "gains/pertes" par
    niveau.
- Resultat:
  - succes;
  - le document couvre maintenant a la fois:
    - la structure des artefacts;
    - la lecture des obligations;
    - la reduction progressive d'un meme contenu semantique.
- Realisations:
  - ajout d'une nouvelle figure:
  - `docs/assets/delay_int_single_tick.dot`;
  - `docs/assets/delay_int_single_tick.svg`;
  - regeneration du PDF:
    - `docs/ir_obligations_etude_delay_int_2026-03-13.pdf`.

### Tentative 3 (ouverture d'un support de clarification `Resume.md`)
- Objectif:
  - disposer d'un fichier court et stable pour consigner au fil des echanges
    les points a tirer au clair sur Kairos.
- Realisation:
  - creation de `Resume.md` a la racine du depot.
- Intention:
  - y ajouter progressivement les points fixes explicitement par la discussion,
    sans melanger ce support avec le cahier de laboratoire.

### Tentative 4 (premier point stabilise dans `Resume.md`)
- Point ajoute:
  - toute execution concrete du programme induit un chemin dans l'automate
    produit, sous hypothese de construction correcte et de semantique de tick
    coherente;
  - la reciproque n'est vraie que pour les chemins realisables du produit.

## 2026-03-12

### Tentative 3 (abaissement explicite de `pre_k` avant Why et premiere IR relationnelle)
- Objectif:
  - regler une dette d'architecture identifiee explicitement:
    - `pre(x,k)` ne devait plus etre interprete dans le backend Why,
      mais etre deja abaisse vers des variables symboliques explicites avant
      la traduction Why3;
  - appliquer le plan de transition:
    - inventaire des dependances `__aut_state` / `Aut*`,
    - definition d'une premiere IR relationnelle,
    - choix d'un cas pilote minimal.
- Demarche suivie:
  - lecture du point de bascule reel `HPreK -> __pre_k...`:
    - `Collect.build_pre_k_infos`,
    - `product_kernel_ir`,
    - `why_env`,
    - `why_compile_expr`;
  - ajout dans `Fo_specs` de fonctions d'abaissement:
    - `lower_hexpr_pre_k`,
    - `lower_fo_pre_k`,
    - `lower_ltl_pre_k`;
  - rebranchement de `product_kernel_ir` pour:
    - abaisser les `FactFormula` des clauses kernel avant export backend;
    - abaisser les resumes de tick exportes;
    - introduire `relational_generated_clauses`, premiere IR de preuve sans
      `FactGuaranteeState`;
  - documentation separee:
    - inventaire des dependances residuelles;
    - note de cadrage du cas pilote `toggle`.
- Resultat:
  - succes partiel mais important;
  - le build `bin/cli/main.exe` repasse apres les changements;
  - les clauses kernel exportees et les resumes exportes ne laissent plus Why
    interpreter directement `HPreK` sur ce chemin.
- Realisations code:
  - `lib_v2/runtime/core/logic/fo/fo_specs.{ml,mli}`:
    - nouvelles fonctions d'abaissement explicite des `pre_k`;
  - `lib_v2/runtime/middle_end/product/product_kernel_ir.{ml,mli}`:
    - clauses kernel abaissees avant export;
    - ajout de `relational_generated_clauses`;
    - resumes `callee_tick_abi` abaisses avant export;
  - documentation:
    - `docs/architecture_transition_inventory_2026-03-12.md`;
    - `docs/relational_proof_pilot_toggle_2026-03-12.md`.
- Inventaire residuel retenu:
  - dette encore presente dans:
    - instrumentation/contracts produit,
    - `generated_clause_ir` legacy avec `FactGuaranteeState`,
    - backend Why (`why_contracts`, `emit`, `why_env`, `why_call_plan`),
    - ABI modulaire des `call`.
- Cas pilote retenu:
  - `tests/without_calls/ok/inputs/toggle.kairos`
  - justification:
    - pas de `call`,
    - pas de `pre`,
    - petit residu logique,
    - bon support pour reconstruire un encodage de preuve sans `Aut*`.
- Conclusion:
  - la dette "Why interprete encore `pre_k`" a commence a etre reglee
    correctement;
  - l'architecture active reste transitoire tant que
    `relational_generated_clauses` n'est pas devenue l'entree principale du
    backend Why.

### Tentative 4 (activation du chemin Why relationnel sans repli legacy)
- Objectif:
  - faire consommer par le backend Why l'IR relationnelle active au lieu du
    vieux chemin centre sur `FactGuaranteeState`;
  - valider le cas pilote `toggle`, puis etendre a `without_calls`.
- Resultat:
  - succes partiel substantiel;
  - echec residuel sur `credit_balance_monitor`.
- Realisations:
  - `why_contracts.ml` consomme maintenant le chemin
    `relational_generated_clauses` pour les resumes kernel actifs;
  - les invariants de programme ont ete reintroduits en precondition helper
    uniquement sous la forme:
    - `st = <State> -> invariant_de_programme`,
    sans indexation par `Aut*`;
  - les disjonctions de premisses relationnelles sont eclatees en plusieurs
    clauses plus petites dans `product_kernel_ir.ml`.
- Verifications ciblees obtenues:
  - `toggle.kairos` : `OK`;
  - `require_delay_bool.kairos` : `OK`;
  - `armed_delay.kairos` : `OK`;
  - `armed_fault_monitor.kairos` : `OK`;
  - `armed_delay__bad_code.kairos` : `INVALID` apres retrait d'une
    simplification trop agressive.
- Echec/limite restante:
  - `credit_balance_monitor.kairos` reste `FAILED` a `5s`;
  - le noyau restant se situe sur plusieurs buts `step_from_run'vc`;
  - une tentative de simplification generique des formules relationnelles a
    introduit une vraie regression de correction:
    - une clause `OriginSafety` de `armed_delay` devenait vacuement vraie par
      simplification de sa garde en `FFalse`;
    - cette tentative a ete retiree immediatement.
- Conclusion:
  - le chemin relationnel actif est maintenant assez solide pour plusieurs cas
    directeurs et garde-fous;
  - `credit_balance_monitor` est le verrou principal restant sur
    `without_calls/ok` avant une campagne complete propre.

### Tentative 2 (requalification architecturale du pipeline de preuve)
- Objectif:
  - requalifier explicitement l'architecture courante apres clarification du
    point cible:
    - pas de monitoring execute,
    - pas de structuration des preuves par etats `Aut*`,
    - utilisation du produit uniquement comme outil de derivation de clauses
      relationnelles.
- Demarche suivie:
  - relecture critique des residus Why en cours (`toggle`, `reset_zero_sink`);
  - comparaison avec l'intention de l'utilisateur et avec la lecture
    relationnelle du noyau Rocq;
  - correction des regles du depot dans `AGENTS.md`;
  - mise a jour du cadre methodologique pour figer la branche actuelle comme
    branche de transition.
- Resultat:
  - succes sur la clarification architecturale;
  - aucune nouvelle tentative locale de "raffinage" du pipeline moniteur n'est
    retenue comme direction cible.
- Constats:
  - l'etat courant de `codex/spot-automata-migration` reste utile comme
    branche de transition:
    - format `.kobj`,
    - `import`,
    - separation des suites `with_calls` / `without_calls`,
    - clauses `OriginSourceProductSummary`,
    - nettoyage partiel du backend Why;
  - en revanche, cette branche ne doit plus etre consideree comme la forme
    finale du pipeline de preuve tant qu'elle reste semantiquement structuree
    autour de `__aut_state` / `Aut*`;
  - les derniers residus sur `toggle` et `reset_zero_sink` ne doivent plus
    servir de pretexte a raffiner cette architecture transitoire.
- Decision:
  - figer l'etat courant comme branche de transition;
  - ne plus investir dans le "monitoring execute" comme support de preuve;
  - preparer un retrait explicite de `__aut_state` / `Aut*` du pipeline actif.
- Plan de retrait retenu:
  - etape 1:
    - inventaire des points ou `__aut_state` / `Aut*` restent visibles dans:
      - IR produit,
      - clauses generees,
      - backend Why,
      - resumes modulaires;
  - etape 2:
    - definir une IR relationnelle cible qui n'encode plus les resumes de
      preuve par etat automate, mais par faits explicites:
      - preconditions locales,
      - relation source/cible,
      - faits exportables sur sorties et memoires;
  - etape 3:
    - choisir un cas pilote minimal et le reconstruire sans etat moniteur;
  - etape 4:
    - etendre ensuite au reste de `without_calls`, puis a `with_calls`.
- Cas pilote choisi:
  - `tests/without_calls/ok/inputs/toggle.kairos`
  - raison:
    - produit simple,
    - peu d'etats programme,
    - residu actuel assez local,
    - bon candidat pour reconstruire une preuve purement relationnelle sans
      support `Aut*`.

### Tentative 1 (rapport PDF detaille d'architecture et d'implementation)
- Objectif:
  - produire un rapport PDF tres detaille sur l'architecture du programme et
    sur les details d'implementation du depot `kairos-dev`.
- Demarche suivie:
  - inspection des notes d'architecture deja presentes a la racine;
  - lecture des points d'entree publics:
    - `bin/cli/cli_v2.ml`,
    - `bin/lsp/kairos_lsp.ml`,
    - `pipeline.mli`,
    - `pipeline_v2_indep.mli`;
  - lecture des modules pivots de l'orchestration:
    - `pipeline_v2_indep.ml`,
    - `engine_service.ml`,
    - `frontend.ml`;
  - lecture des modules semantiques:
    - `product_build.ml`,
    - `product_kernel_ir.mli`;
  - lecture des modules backend/proof:
    - `why_runtime_view.ml`,
    - `why_env.ml`,
    - `why_core.ml`,
    - `why_call_plan.ml`,
    - `why_contracts.ml`,
    - `emit.ml`,
    - `why_prove.ml`;
  - lecture des modules de modularite:
    - `kairos_object.ml`,
    - `modular_imports.ml`.
- Resultat:
  - succes;
  - redaction d'un rapport source:
    - `docs/rapport_architecture_kairos_2026-03-12.md`;
  - generation attendue d'un PDF associe a partir de ce rapport.
- Constats architecturaux principaux:
  - le centre de gravite du systeme est bien le pipeline semantique et non
    l'emission Why3 seule;
  - `product_kernel_ir` joue le role de source de verite backend-agnostic;
  - `why_runtime_view` sert d'interface d'adaptation entre IR semantique et
    backend Why;
  - le backend Why reste la zone la plus complexe, surtout autour des contrats
    et des appels d'instance;
  - le support `.kobj` formalise correctement une modularite par artefacts
    compiles.
- Limites reconnues:
  - rapport fonde sur l'inspection du code et des interfaces;
  - pas de relecture exhaustive de tous les modules du depot;
  - pas de validation formelle complete de toutes les preuves Rocq.

## 2026-03-11

### Tentative 5 (objets `.kobj`, `import`, modularite des `call`)
- Objectif:
  - introduire un vrai chemin modulaire pour les `call`:
    - format objet `.kobj`,
    - syntaxe `import`,
    - resolution des callees via objets compiles,
    - preuve locale du caller sur resume compile.
- Resultat:
  - progression substantielle, mais blocage restant cote emission/type-checking
    Why3 des projections de champs sur records importes.
- Realisations:
  - syntaxe source:
    - ajout de `import "…";` dans le lexer/parser/frontend;
  - pipeline:
    - chargement explicite des `.kobj` via `modular_imports`;
    - propagation des `imported_summaries` jusqu'au middle-end et au backend;
    - nouveau chemin `compile_object` et option CLI `--emit-kobj`;
  - format objet:
    - ajout de `kairos_object.{ml,mli}`;
    - serialisation JSON versionnee backend-agnostic;
    - contenu:
      - metadonnees,
      - signature,
      - IR normalise,
      - resume modulaire de tick,
      - invariants exportes,
      - `pre_k_map`,
      - `delay_spec`;
  - resume modulaire:
    - `product_kernel_ir` enrichi avec:
      - `node_signature_ir`,
      - `exported_node_summary_ir`,
      - `callee_tick_abi_ir`,
      - export/import des resumes de callees;
  - backend Why:
    - abandon du faux `step` importe;
    - `ActionCall` rebranche sur un `any` local contraint par le resume de
      tick compile;
    - debut d'introduction de getters explicites pour eviter les projections
      fragiles sur records importes.
- Tentatives infructueuses documentees:
  - tentative A:
    - modeliser l'appel importe par un faux module externe avec un `step`
      abstrait Why;
    - echec avec erreur Why "this expression should not produce side effects";
    - cause:
      - ce chemin restait ad hoc backend-specific et ne modelisait pas
        proprement l'appel local au point d'usage.
  - tentative B:
    - ne faire retourner par le `any` local que le record `vars` du callee,
      puis relire les sorties via projections sur ce record importe;
    - echec avec symboles Why non resolus sur les champs importes
      (`__delay_core_outv`, `__delay_core_st`, etc.);
    - cause:
      - les projections de records importes ne se laissent pas reutiliser
        simplement dans les termes/programmes generes via l'API Ptree.
  - tentative C:
    - introduire des getters programmes puis des getters logiques explicites
      dans les modules importes;
    - echec persistant de resolution Why sur ces symboles depuis le module
      caller;
    - conclusion provisoire:
      - la couture correcte doit probablement eviter de dependre des projections
        de records importes dans les obligations locales, ou produire une ABI
        Why encore plus explicite.
- Corrections deja acquises malgre le blocage:
  - les exemples multi-noeuds `ok`/`ko` ont ete separes en plusieurs fichiers
    avec imports explicites;
  - les `.kobj` exportent maintenant:
    - les memoires `pre_k`,
    - une signature runtime plus proche de l'etat persistant reel;
  - les faits de moniteur interne (`__aut_state`, `FactGuaranteeState`) ont ete
    commences a etre filtres hors de l'ABI exportee, pour ne pas faire fuiter
    un etat interne non expose.
- Validation partielle:
  - `dune build bin/cli/main.exe` : OK a plusieurs reprises pendant le travail;
  - emission `.kobj` : OK;
  - parsing `import` : OK;
  - preuve modulaire importee:
    - encore bloquee sur le type-checking Why des acces au state resume.
- Conclusion honnete:
  - la structure modulaire est largement en place;
  - le dernier verrou critique est dans la representation Why des valeurs
    d'etat/sortie du callee importe au point d'appel;
  - la campagne `ok/ko` complete n'est pas encore revalidee.

### Sujet
Reduction structurelle du vieux chemin `why_contracts` pour les obligations de
transition sur le chemin `kernel-first`.

### Tentative 0 (factorisation des blocs de transition inactifs)
- Objectif: ne plus seulement neutraliser semantiquement certains blocs
  historiques sur le chemin `kernel-first`, mais eviter de les calculer du tout
  dans `why_contracts.ml`.
- Resultat: succes.
- Realisations:
  - regroupement dans un seul tuple de calcul:
    - `transition_requires_pre_terms`,
    - `transition_requires_pre`,
    - `transition_requires_post`,
    - `state_post`,
    - `state_post_terms`,
    - `state_post_terms_vcid`,
    - `transition_post_to_pre`;
  - sur le chemin `kernel-first`, ce bloc vaut directement des listes vides;
  - sur le chemin legacy, le calcul historique est preserve inchange.
- Incident intermediaire:
  - premiere passe avec erreur de portee sur `pre_contract_user` /
    `post_contract_user` et reconstruction de `post_contract`;
  - correction appliquee sans changement de semantique.
- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`,
    - `bin/lsp/kairos_lsp.exe`,
    - `bin/ide/obcwhy3_ide.exe`;
  - campagne CLI OK:
    - `delay_int.kairos`: `failed=0`;
    - `resettable_delay.kairos`: `failed=0`;
    - `delay_int_instance.kairos`: `failed=0`.
- Conclusion:
  - le vieux chemin des obligations de transition recule encore d'un cran;
  - la prochaine reduction utile vise maintenant les derniers blocs encore
  actifs mais redondants du chemin legacy, sous garde
  `CoverageExplicit/CoverageFallback`.

### Tentative 0 bis (factorisation du bloc legacy instances/sorties)
- Objectif: regrouper les derniers calculs legacy encore epars autour:
  - des invariants d'instance,
  - des liens d'instance,
  - des liens de sortie,
  pour qu'ils soient court-circuites comme un seul bloc sur le chemin
  `kernel-first`.
- Resultat: succes.
- Realisations:
  - regroupement dans un tuple unique de:
    - `instance_invariants`,
    - `instance_input_links_pre`,
    - `instance_input_links_post`,
    - `instance_delay_links_inv`,
    - `output_links`,
    - `first_step_links`,
    - `first_step_init_link_pre`,
    - `link_invariants`;
  - sur le chemin `kernel-first`, seul `instance_delay_links_inv` reste derive
    de l'IR abstrait, tout le reste est vide;
  - sur le chemin legacy, le comportement est preserve.
- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`,
    - `bin/lsp/kairos_lsp.exe`,
    - `bin/ide/obcwhy3_ide.exe`;
  - campagne CLI OK:
    - `delay_int.kairos`: `failed=0`;
    - `resettable_delay.kairos`: `failed=0`;
    - `delay_int_instance.kairos`: `failed=0`.
- Conclusion:
  - le chemin `kernel-first` n'evalue plus les anciens blocs d'instances et de
    sorties disperses;
  - la prochaine reduction utile est maintenant de traiter la couche de labels
  et de contexte diagnostique pour qu'elle arrete aussi de traquer des blocs
  legacy vides.

### Tentative 0 ter (labels compacts sur le chemin `kernel-first`)
- Objectif: faire en sorte que la couche diagnostique Why n'arrete pas
  d'embarquer des familles legacy vides quand le backend est deja sur le chemin
  `kernel-first`.
- Resultat: succes.
- Realisations:
  - ajout d'un drapeau `kernel_first` dans `Why_diagnostics.label_context`;
  - en mode `kernel_first`, `build_labels` ne construit plus que les familles
    pertinentes:
    - `Transition requires`,
    - `Internal links`;
  - les familles legacy:
    - `User contract requires/ensures`,
    - `Instance invariants`,
    - `Instrumentation`,
    - `pre_k history`,
    - etc.
    ne sont plus construites dans ce mode.
- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`,
    - `bin/lsp/kairos_lsp.exe`,
    - `bin/ide/obcwhy3_ide.exe`;
  - campagne CLI OK:
    - `delay_int.kairos`: `failed=0`;
    - `resettable_delay.kairos`: `failed=0`;
    - `delay_int_instance.kairos`: `failed=0`.
- Conclusion:
  - le contexte diagnostique est maintenant aligne avec la reduction effective
    du chemin Why historique;
  - la prochaine etape utile est d'identifier les derniers morceaux encore
    vraiment dependants de l'ancien OBC annote, plutot que de continuer a
    seulement nettoyer des coquilles vides.

### Tentative 1 (identification des derniers points de dependance reels)
- Objectif: isoler les derniers morceaux qui dependent encore reellement de
  l'OBC annote comme pivot de preuve, au lieu de continuer a nettoyer des
  couches auxiliaires.
- Resultat: succes.
- Realisations:
  - audit cible des modules:
    - `why_contracts.ml`,
    - `why_env.ml`,
    - `why_core.ml`,
    - `emit.ml`,
    - plus la couche pipeline/debug;
  - redaction d'une note technique:
    [ARCHITECTURE_REMAINING_OBC_DEPENDENCIES.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/ARCHITECTURE_REMAINING_OBC_DEPENDENCIES.md)
- Conclusion principale:
  - le vrai verrou n'est plus dans les labels ni dans les diagnostics;
  - il reste dans le runtime Why lui-meme:
    - construction d'environnement dans `why_env.ml`,
    - execution des transitions dans `why_core.ml`,
    - fallback legacy dans `why_contracts.ml`.
- Consequence:
  - la prochaine migration doit viser un runtime/program view Why derive du
    nouvel IR abstrait, et non plus `Ast.node` annote comme entree native.

### Tentative 2 (clarification de la frontiere runtime abstraite / adaptateur Why)
- Objectif: fixer proprement la frontiere entre:
  - l'IR abstrait backend-agnostic;
  - la vue runtime adaptee a Why;
  pour ne pas continuer le refactoring sur une interface implicite.
- Resultat: succes.
- Realisations:
  - redaction d'une note d'architecture:
    [ARCHITECTURE_WHY_RUNTIME_VIEW.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/ARCHITECTURE_WHY_RUNTIME_VIEW.md)
- Clarification obtenue:
  - l'IR abstrait reste la source de verite semantique;
  - Why recoit une `why_runtime_view` derivee de cet IR;
  - `why_env` doit consommer cette vue pour definir les representations Why;
  - `why_core` doit compiler les transitions/calls depuis cette vue;
  - `why_contracts` doit compiler les clauses abstraites, sans relire
    l'ancienne instrumentation comme source semantique.
- Conclusion:
  - le prochain chantier n'est plus conceptuel;
  - il consiste a definir les types OCaml concrets de `why_runtime_view` puis a
    porter `why_env.ml` dessus.

### Tentative 3 (types OCaml de `why_runtime_view` + premier portage de `why_env`)
- Objectif: materialiser l'interface `why_runtime_view` dans le code, puis faire
  de `why_env` un consommateur de cette vue, sans casser le chemin courant.
- Resultat: succes avec shim transitoire explicite.
- Realisations:
  - ajout du module:
    - [why_runtime_view.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.mli)
    - [why_runtime_view.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml)
  - types introduits:
    - `port_view`,
    - `instance_view`,
    - `runtime_transition_view`,
    - `Why_runtime_view.t`;
  - ajout dans [why_env.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.mli) de:
    - `prepare_runtime_view`;
  - `prepare_node` devient maintenant un adaptateur:
    - `Ast.node -> Why_runtime_view.t -> prepare_runtime_view`.
- Incident intermediaire:
  - premiere version du collecteur `monitor_state_ctors` de
    `why_runtime_view` etait trop restrictive et ne retrouvait plus `Aut1`;
  - correction appliquee en realignant le collecteur sur le comportement
    historique tant que le shim legacy existe.
- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`,
    - `bin/lsp/kairos_lsp.exe`,
    - `bin/ide/obcwhy3_ide.exe`;
  - campagne CLI OK:
    - `delay_int.kairos`: `failed=0`;
    - `resettable_delay.kairos`: `failed=0`;
    - `delay_int_instance.kairos`: `failed=0`.
- Etat honnete:
  - `why_env` est bien porte derriere l'interface `why_runtime_view`;
  - a ce stade, la vue contenait encore un shim transitoire `source_node`;
  - le prochain vrai pas etait donc de retirer cette dependance en portant
    `why_core.ml` sur la vue runtime.

### Tentative 4 (portage de `why_core` sur `why_runtime_view` + suppression du shim)
- Objectif: faire compiler l'execution des transitions Why depuis
  `why_runtime_view.runtime_transition_view`, puis supprimer `source_node` de la
  vue runtime.
- Resultat: succes.
- Realisations:
  - enrichissement de `runtime_transition_view` avec:
    - `requires`,
    - `ensures`,
    - `ghost`,
    - `instrumentation`;
  - reconstruction complete de `Ast.node` depuis `why_runtime_view` dans
    `prepare_runtime_view`, sans `source_node`;
  - ajout de `runtime_view` dans `Why_types.env_info`;
  - `why_core.ml` compile maintenant:
    - `Why_runtime_view.runtime_transition_view list`
    au lieu de `Ast.transition list`;
  - `emit.ml` branche `compile_transitions` sur
    `info.runtime_view.transitions`.
- Incidents intermediaires:
  - ambiguite de typage OCaml dans `why_core.ml` sur les champs
    `ghost`/`src_state`;
  - correction par annotations explicites de type dans les boucles/fonctions
    recursives.
- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`,
    - `bin/lsp/kairos_lsp.exe`,
    - `bin/ide/obcwhy3_ide.exe`;
  - campagne CLI OK:
    - `delay_int.kairos`: `failed=0`;
    - `resettable_delay.kairos`: `failed=0`;
    - `delay_int_instance.kairos`: `failed=0`.
- Conclusion:
  - `why_core` ne depend plus du `Ast.transition` annote comme entree native;
  - le shim `source_node` a ete supprime de `why_runtime_view`;
  - le prochain vrai verrou restant est maintenant du cote de
    `why_contracts.ml`.

### Tentative 5 (premiere bascule de `why_contracts` sur `why_runtime_view`)
- Objectif: faire en sorte que `why_contracts.ml` consomme explicitement la vue
  runtime abstraite, plutot que `info.node` comme source principale.
- Resultat: succes.
- Realisations:
  - ajout de l'entree:
    `build_contracts_runtime_view` dans
    [why_contracts.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.mli)
    et
    [why_contracts.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml);
  - introduction d'un adaptateur local
    `ast_transition_of_runtime`;
  - remplacement dans `why_contracts.ml` des usages directs du nœud annote par
    la vue runtime pour:
    - les transitions,
    - les instances,
    - les sorties,
    - les invariants utilisateur,
    - les invariants d'etat,
    - les garanties utilisateur;
  - `build_contracts` devient maintenant un simple wrapper vers
    `build_contracts_runtime_view ... info.runtime_view`.
- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`,
    - `bin/lsp/kairos_lsp.exe`,
    - `bin/ide/obcwhy3_ide.exe`;
  - campagne CLI OK:
    - `delay_int.kairos`: `failed=0`;
    - `resettable_delay.kairos`: `failed=0`;
    - `delay_int_instance.kairos`: `failed=0`.
- Etat honnete:
  - il reste encore du fallback legacy dans la logique de contrats;
  - mais il est maintenant alimente depuis `why_runtime_view`, pas depuis
    `info.node` comme source de verite principale.

### Tentative 6 (retrait de `info.node` de l'ABI Why active)
- Objectif: sortir `info.node` de `Why_types.env_info` maintenant que
  `why_env`, `why_core` et `why_contracts` savent travailler via
  `why_runtime_view`.
- Resultat: succes.
- Realisations:
  - suppression de `node : Ast.node` dans:
    - [why_types.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_types.mli)
    - [why_types.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_types.ml)
  - ajustement de [why_env.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.ml)
    pour ne plus le produire;
  - ajustement de [emit.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml)
    pour reutiliser le nœud d'entree local au lieu de `info.node`;
  - dernier usage residuel remplace dans
    [why_contracts.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml)
    par `runtime.node_name`.
- Clarification d'architecture:
  - le fallback legacy restant dans `why_contracts.ml` est maintenant
    explicitement commente comme compatibilite transitoire;
  - l'ABI active du backend Why ne transporte plus le nœud annote brut.
- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`,
    - `bin/lsp/kairos_lsp.exe`,
    - `bin/ide/obcwhy3_ide.exe`;
  - campagne CLI OK:
    - `delay_int.kairos`: `failed=0`;
    - `resettable_delay.kairos`: `failed=0`;
    - `delay_int_instance.kairos`: `failed=0`.
- Conclusion:
  - le nœud OBC annote n'est plus dans l'ABI Why active;
  - le vrai residu restant est maintenant interne a `why_contracts.ml`,
  dans la logique fallback legacy elle-meme, et non plus dans l'interface.

### Tentative 7 (isolation explicite du fallback legacy de transitions)
- Objectif: sortir le fallback legacy des obligations de transition du flux
  principal de `why_contracts.ml`, pour qu'il soit visible comme bloc
  transitoire explicite et non plus comme logique melangee au chemin principal.
- Resultat: succes.
- Realisations:
  - ajout d'un type `legacy_transition_fallback`;
  - extraction d'un helper dedie:
    `compute_legacy_transition_fallback`;
  - remplacement du gros bloc inline par:
    - appel au helper,
    - deconstruction locale du resultat.
- Incident intermediaire:
  - deux ajustements de typage ont ete necessaires:
    - ne pas passer `normalize_ltl` comme fonction abstraite, car son resultat
      est un record;
    - reinternaliser `conj_terms` dans le helper pour eviter une dependance
      d'ordre de definitions.
- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`,
    - `bin/lsp/kairos_lsp.exe`,
    - `bin/ide/obcwhy3_ide.exe`;
  - campagne CLI OK:
    - `delay_int.kairos`: `failed=0`;
    - `resettable_delay.kairos`: `failed=0`;
    - `delay_int_instance.kairos`: `failed=0`.
- Conclusion:
  - le fallback legacy de transitions est maintenant clairement isole;
  - le residu suivant a traiter est le bloc legacy des liens/invariants
    d'instance dans `why_contracts.ml`.

### Sujet
Deblocage du backend Why pour `instances/call` sur le vrai fixture
`delay_int_instance.kairos`.

### Tentative 1 (lecture du Why brut pour sortir du diagnostic a l'aveugle)
- Objectif: voir le texte Why exact du site d'appel, sans passer par les
  erreurs tronquees de la preuve.
- Resultat: succes.
- Realisations:
  - ajout d'un utilitaire local
    `bin/dev/emit_why_debug.ml` et de son stanza `bin/dev/dune`;
  - emission du Why brut pour
    `tests/ok/inputs/delay_int_instance.kairos`.
- Observation cle:
  - le verrou initial etait bien au site d'appel Why de la forme
    `Delay_core.__delay_core_outv vars.__delay_int_instance_d`.

### Tentative 2 (stabilisation de `SCall` avec instance locale)
- Objectif: eviter les projections Why fragiles sur un champ imbrique
  `vars.<instance>`.
- Resultat: succes partiel utile.
- Realisations:
  - dans `why_core.ml`, `SCall` cree maintenant un `let __call_inst_*` avant
    l'appel;
  - adaptation de la signature du callback `call_asserts` pour distinguer:
    - le nom d'instance source (lookup),
    - le nom d'acces effectif dans le codegen;
  - ajustement de `support.ml` pour supporter les acces d'instance sur:
    - une vraie variable de record courante,
    - une variable locale simple.
- Effet observe:
  - le Why brut caller est passe a une forme saine:
    `let __call_inst_d = vars.__delay_int_instance_d in ...`

### Tentative 3 (suppression de la projection de sortie au site d'appel)
- Objectif: ne plus lire les sorties du callee via un acces de champ Why
  inter-module.
- Resultat: succes partiel utile.
- Realisations:
  - dans `why_env.ml`, `step` retourne maintenant les sorties courantes;
  - dans `why_core.ml`, pour les calls mono-sortie, le caller recupere la
    sortie via:
    - `let __call_res_* = Delay_core.step __call_inst_d x in ...`
  - correction de `ret_expr` pour qu'il retourne la valeur
    `vars.<out>` et non le symbole de projection.
- Effet observe:
  - l'ancien verrou `__delay_core_outv` a disparu comme probleme dominant.

### Etat courant honnete
- Nouveau verrou isole:
  - `unbound function or predicate symbol 'Delay_core.__delay_core_st'`
- Interpretation:
  - le site d'appel runtime n'est plus le principal probleme;
  - les termes logiques / contrats d'instance emettent encore des projections
    d'etat de type `Delay_core.__delay_core_st`, donc l'ancien chemin n'est pas
    completement remplace.
- Conclusion:
  - progression reelle sur `instances/call`;
  - pas encore fini;
  - la prochaine cible technique est de migrer les relations d'etat d'instance
    hors des projections Why inter-modules restantes.

## 2026-03-10

### Sujet
Deuxieme phase du diagnostic d'echec: analyse structuree Why3, borne CLI
effective et retouche de la vue Explain Failure.

### Tentative 1 (remplacement du slice lexical par une analyse structuree Why3)
- Objectif: ne plus classer les hypotheses pertinentes uniquement a partir d'un
  recouvrement lexical, mais a partir de la structure normalisee des termes
  Why3.
- Resultat: succes.
- Realisations:
  - ajout dans `why_prove` d'un export `task_structured_sequents` contenant:
    - texte du terme,
    - symboles,
    - operateurs,
    - quantificateurs,
    - indicateur arithmetique,
    - taille du terme;
  - remplacement dans `Pipeline_v2_indep` du score lexical par un score de
    recouvrement structurel symbole / operateur / quantificateur;
  - instrumentation des hypotheses Why3 generees dans `emit.ml` avec:
    - `hid:<id>`;
    - `hkind:pre|post`;
    - `origin:<label>`;
  - extraction de ces marqueurs dans `why_prove` pour les sequents structures;
  - enrichissement du diagnostic type avec:
    - `goal_symbols`,
    - `analysis_method`,
    - `unused_hypotheses`;
  - mise a jour du protocole LSP et des types VS Code pour transporter ces
    champs proprement.
- Validation:
  - build sequentiel CLI/LSP/IDE/extension;
  - sur `tests/ok/inputs/delay_int.kairos`, les traces failed exposees
    remontent maintenant un contexte minimal et des hypotheses depriorisees
    derives de l'AST Why3, sans retour a `unknown`.
- Limite:
  - il ne s'agit pas encore d'un unsat core ou d'une preuve d'utilisation
    logique exacte; la methode est explicitee comme telle dans l'UI.

### Tentative 2 (borne CLI reelle pour les cas lourds)
- Objectif: faire en sorte que le mode JSON de diagnostic soit effectivement
  bornable en temps/volume sur les cas lourds, et pas seulement tronque a la
  fin.
- Resultat: succes partiel utile.
- Realisations:
  - ajout des options:
    - `--proof-traces-failed-only`,
    - `--max-proof-traces`,
    - `--proof-traces-fast`;
  - ajout d'un champ de config pipeline `max_proof_goals` afin que la borne
    coupe la boucle de preuve elle-meme;
  - en mode `fast`, desactivation des gros artefacts texte VC/SMT/monitor pour
    conserver une iteration scriptable.
- Validation:
  - `tests/ok/inputs/delay_int2.kairos` avec
    `--proof-traces-failed-only --max-proof-traces 10 --timeout-s 1`:
    sortie bornee, 1 echec retourne dans la fenetre prouvee, pas de parcours
    complet des 253 goals;
  - `tests/ko/inputs/light_latch.kairos` avec
    `--proof-traces-failed-only --max-proof-traces 20 --proof-traces-fast --timeout-s 1`:
    terminaison en ~29s, pas de `Stack overflow`, 1 trace failed retournee.
- Limite:
  - la borne suit l'ordre de preuve des goals; avec un petit `max`, on peut
    terminer sans rencontrer d'echec si les premiers goals sont valides.

### Tentative 4 (replay glouton sur hypotheses instrumentees)
- Objectif: passer d'un simple classement des hypotheses a un test effectif de
  dependance, meme sans unsat core solveur.
- Resultat: succes partiel utile.
- Realisations:
  - ajout dans `why_prove` d'une procedure
    `minimize_failing_hypotheses` qui:
    - cible un goal split Why3;
    - isole les hypotheses Kairos instrumentees `hid`;
    - retire gloutonnement chaque hypothese candidate;
    - rejoue localement la VC;
    - conserve seulement les hypotheses dont le retrait ferait redevenir la VC
      `valid`;
  - branchement de ce replay dans `Pipeline_v2_indep` pour enrichir
    `analysis_method`, `relevant_hypotheses` et `unused_hypotheses` sur les
    goals non valides.
- Validation:
  - build CLI/LSP/IDE ok;
  - sur `delay_int.kairos`, les diagnostics failed annoncent bien une methode
    de type `greedy replay-minimization`.
- Limite:
  - sur le cas observe, le noyau minimal peut etre vide si les hypotheses
    Kairos instrumentees sont toutes inutiles a reproduire l'echec; dans ce cas
    le diagnostic retombe sur l'analyse structurelle Why3.

### Tentative 5 (ciblage focalise + separation Kairos / Why3)
- Objectif: rendre le diagnostic utilisable goal par goal, et distinguer
  explicitement ce qui vient du modele Kairos de ce qui vient du contexte Why3
  auxiliaire.
- Resultat: succes.
- Realisations:
  - ajout du ciblage pipeline/CLI/LSP par `selected_goal_index`;
  - ajout CLI `--proof-trace-goal-index`;
  - correction du raccord `goal_results` / `proof_traces` quand un seul goal est
    prouve;
  - ajout dans `proof_diagnostic` de:
    - `kairos_core_hypotheses`,
    - `why3_noise_hypotheses`;
  - ajout d'un bouton `Focused Diagnosis` dans `Explain Failure` cote VS Code.
- Validation:
  - `delay_int.kairos` avec `--proof-trace-goal-index 5`: 1 trace retournee,
    `goal_index = 5`, `status = failure`;
  - `light_latch.kairos` avec `--proof-trace-goal-index 15 --proof-traces-fast
    --timeout-s 1`: 1 trace retournee en ~25s, sans `Stack overflow`.

### Tentative 3 (retouche Explain Failure)
- Objectif: faire remonter la nouvelle analyse dans la vue VS Code sans bruit.
- Resultat: succes.
- Realisations:
  - renommage de la section principale en `Minimal Relevant Context`;
  - ajout des panneaux:
    - `Goal Symbols`,
    - `Deprioritized Hypotheses`,
    - `Analysis Method`;
  - conservation de la navigation Source / OBC / Why / VC / SMT / dump.
- Conclusion:
  - la phase 2 est materialisee dans le code, testee et documentee;
  - la limite principale restante est qualitative: contexte structurel utile,
    mais pas encore preuve minimale logique certifiee.

## 2026-03-09

### Sujet
Diagnostic structure des echecs de preuve et tracabilite Source -> OBC -> Why -> VC -> SMT.

### Tentative 1 (modele de trace backend/protocole/CLI/VS Code)
- Objectif: introduire une structure typee de trace de preuve exploitable en
  CLI, LSP et VS Code, au lieu de simples tuples de goals.
- Resultat: succes partiel significatif.
- Realisations:
  - ajout de types `text_span`, `proof_diagnostic`, `proof_trace` dans:
    - `lib_v2/runtime/pipeline/pipeline.mli`,
    - `protocol/lsp_protocol.mli`,
    - l'extension VS Code;
  - enrichissement de `Pipeline_v2_indep` avec:
    - spans OBC exacts via `Obc_emit.compile_program_with_spans`,
    - spans Why via `Emit.emit_program_ast_with_spans`,
    - spans VC/SMT par concatenation structuree,
    - heuristiques de classement des obligations a partir de la taxonomie
      backend,
    - diagnostic humain structure par goal;
  - exposition LSP via `outputsReady` enrichi;
  - ajout CLI `--dump-proof-traces-json` pour iterer sans UI;
  - ajout VS Code:
    - dashboard branche sur `proof_traces`,
    - panel dedie `Explain Failure`,
    - navigation Source / OBC / Why / VC / SMT / dump SMT.
- Limites constatees:
  - une partie des VCs normalises Why3 n'embarque pas encore d'identifiant
    d'origine resolu, donc certains goals restent classes `unknown`;
  - les hypotheses pertinentes sont aujourd'hui un slice lexical du sequent,
    utile mais encore inferieur a une vraie analyse d'usage logique;
  - plusieurs `loc` source restent absentes dans les exemples testes, donc la
    navigation Source n'est pas encore complete sur tous les cas.

### Tentative 2 (validation reelle CLI)
- Objectif: verifier sur des cas non triviaux que les diagnostics produits sont
  coherents et exploitables.
- Resultat: succes partiel renforce.
- Cas verifies:
  - `tests/ok/inputs/delay_int.kairos`:
    - sortie JSON structuree obtenue;
    - apres extension de la provenance `rid` + `wid`, les traces n'ont plus de
      goals `unknown` sur ce cas;
    - traces comprenant `stable_id`, `source`, `obligation_kind`,
      `obligation_family`, `vc_span`, `smt_span`, `dump_path`, diagnostic;
    - presence de goals effectivement en `failure` avec dump SMT et resume
      contextualise.
- Corrections appliquees:
  - ajout du suivi `rid` dans:
    - extraction Why3 des ids de task,
    - spans Why,
    - spans OBC;
  - ajout des `loc` source pour:
    - requires,
    - ensures,
    - coherency goals;
  - remplacement de la serialisation JSON monolithique par une emission
    incrementalement ecrite dans `--dump-proof-traces-json`;
  - ajout d'un timeout CLI explicite `--timeout-s` reutilise par le dump des
    traces de preuve.
- Probleme residuel:
  - `tests/ko/inputs/light_latch.kairos` reste couteux a diagnostiquer en CLI;
    le `Stack overflow` initial n'a plus ete reproduit dans le meme chemin,
    mais le temps de calcul reste eleve sur ce cas.
- Conclusion:
  - la nouvelle chaine de trace est fonctionnelle;
  - la qualite est deja utile sur des cas reels;
  - il reste un point dur de performance/ergonomie sur certains cas `ko`
    volumineux.

### Sujet
Audit initial de l'extension VS Code Kairos contre le serveur LSP, le protocole
et l'UI native GTK, avant refonte produit.

### Tentative 1 (audit croise extension/LSP/UI native)
- Objectif: etablir une matrice factuelle des fonctionnalites deja presentes,
  manquantes ou seulement partielles, sans supposer une parite qui n'existe pas.
- Resultat: succes.
- Constats principaux:
  - l'extension VS Code actuelle est concentree dans un unique fichier
    `extensions/kairos-vscode/src/extension.ts`, avec typage faible
    (`any` sur `outputs`, `automata`, `outline`, `goals`);
  - le serveur LSP expose deja:
    - `hover`, `definition`, `references`, `completion`, `formatting`,
    - `kairos/run`,
    - `kairos/instrumentationPass`,
    - `kairos/obcPass`,
    - `kairos/whyPass`,
    - `kairos/obligationsPass`,
    - `kairos/evalPass`,
    - `kairos/dotPngFromText`,
    - `kairos/outline`,
    - `kairos/goalsTreeFinal`,
    - `kairos/goalsTreePending`,
    - l'annulation JSON-RPC standard `$/cancelRequest`,
    - la progression `$/progress` pendant `kairos/run`;
  - l'UI native exploite deja un ensemble beaucoup plus riche:
    - barre d'outils complete `Build` / `Prove` / `Automates` / `Eval` /
      `Reset` / `Cancel run`,
    - journal local des runs,
    - etat d'execution detaille,
    - fenetre Eval dediee avec ouverture/sauvegarde,
    - fenetre Automates avec 4 graphes (`Program`, `Guarantee`, `Assume`,
      `Product`) et interaction zoom/pan,
    - caches, restauration de session, diff d'Abstract Program,
    - progression live des goals et regroupement par noeud/transition.
- Ecarts critiques releves:
  - pas de `Reset` ni `Cancel run` dans l'extension;
  - pas de fenetre Automata professionnelle, seulement texte + PNG brut;
  - pas de panel Eval dedie;
  - vue Artifacts reduite a une liste de commandes;
  - observabilite faible: pas d'historique local, pas de barre de statut,
    pas d'etat de run robuste;
  - tres peu de preferences VS Code exposees;
  - aucune architecture modulaire cote extension.

### Tentative 2 (strategie retenue)
- Objectif: engager une refonte produit de l'extension, pas un ajout ponctuel
  de commandes.
- Resultat: succes partiel implemente et valide cote extension.
- Strategie retenue:
  - refonte du client VS Code autour d'un etat applicatif type;
  - separation claire:
    - protocole/types,
    - etat des runs,
    - commandes,
    - providers,
    - webviews,
    - rendu automates,
    - preferences;
  - extension du protocole seulement quand l'existant ne suffit pas a livrer
    une UX credible;
  - maintien d'un theme clair par defaut dans les webviews tout en respectant
    les tokens de theme VS Code;
  - validation obligatoire par build extension + build dune + smoke tests.
- Fichiers cibles de l'audit:
  - `extensions/kairos-vscode/package.json`
  - `extensions/kairos-vscode/src/extension.ts`
  - `bin/lsp/kairos_lsp.ml`
  - `protocol/lsp_protocol.ml`
  - `bin/ide/obcwhy3_ide.ml`
- Document d'audit ajoute:
  - `extensions/kairos-vscode/AUDIT_2026-03-09.md`

### Tentative 3 (refonte de l'extension VS Code)
- Objectif: remplacer le client monolithique par une architecture typee avec
  vues/panneaux de travail, observabilite locale et rendu automate serieux.
- Resultat: succes.
- Changements retenus:
  - decoupage de `extensions/kairos-vscode/src/extension.ts` en modules:
    - `types.ts`,
    - `state.ts`,
    - `documents.ts`,
    - `goals.ts`,
    - `providers.ts`,
    - `graphviz.ts`,
    - `panels.ts`;
  - suppression des `any` structurants cote extension;
  - ajout d'un etat applicatif avec:
    - phase de run,
    - historique local,
    - artefacts courants,
    - eval history,
    - previous outputs pour diff OBC;
  - ajout de vues/panneaux:
    - `Runs`,
    - `Automata Studio`,
    - `Proof Dashboard`,
    - `Artifacts Workspace`,
    - `Eval Playground`,
    - `Pipeline View`,
    - `Automata Compare`;
  - ajout de commandes produit:
    - `Cancel Run`,
    - `Reset State`,
    - `Show Run History`,
    - `Diff OBC with Previous Run`,
    - `Open Recent File`,
    - `Export HTML Report`,
    - ouverture directe des panneaux;
  - ajout de keybindings, menus editeur et code lenses;
  - ajout de persistence de session workspace pour les panneaux/historiques;
  - ajout de support open/save de traces dans `Eval`;
  - ajout d'un provider de tasks VS Code pour Build/Prove/Automata;
  - ajout d'exports DOT/SVG/PNG/PDF via Graphviz local.
- Limitations constatees pendant l'implementation:
  - le rendu automate interactif est base sur SVG genere localement via
    `dot`; il n'etend pas encore le protocole LSP pour transporter un modele
    de graphe plus semantique;
  - la comparaison courant/precedent d'automates est actuellement centree sur
    le produit, avec un precedent textuel si aucun rendu precedent n'est
    rehydrate.

### Tentative 4 (documentation produit)
- Objectif: fournir une documentation versionnee couvrant CLI, LSP et extension
  VS Code puis la generer en PDF dans le depot.
- Resultat: succes.
- Livrables:
  - source: `docs/kairos_user_manual.md`
  - PDF: `docs/kairos_user_manual.pdf`
- Commande utilisee:
  - `pandoc docs/kairos_user_manual.md -o docs/kairos_user_manual.pdf --pdf-engine=xelatex`

### Validation
- `cd extensions/kairos-vscode && npm run compile` : succes.
- `pandoc --version` : succes.
- `xelatex --version` : succes.
- generation PDF `docs/kairos_user_manual.pdf` : succes.
- validation OCaml via opam, en sequence:
  - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short` : succes.
  - `opam exec -- dune build bin/cli/main.exe --display=short` : succes.
  - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short` : succes.

### Incident de validation
- Observation:
  - lancer plusieurs `dune build` en parallele dans ce depot laisse des
    processus se bloquer mutuellement.
- Correction:
  - arret des processus de build concurrents lances par erreur;
  - reprise stricte des validations `dune` en sequence.

### Sujet
Suppression du pipeline maison devenu mort apres la migration Spot/Z3.

### Tentative 1 (nettoyage partiel)
- Objectif: conserver les nouveaux backends Spot/Z3 mais laisser les anciens
  modules hors du chemin principal pour eventuel fallback.
- Resultat: ecarte.
- Cause:
  - la facade `Automaton_engine` gardait encore la structure de backend
    interchangeable historique;
  - `Automaton_core` reexportait toujours les API de normalisation/progression
    LTL;
  - plusieurs appels conservaient `simplify_iexpr` sur les gardes de programme
    et de rendu, donc le code maison restait semantiquement actif.

### Tentative 2 (succes)
- Objectif: retirer effectivement du code et du build les briques legacy.
- Resultat: succes.
- Suppressions retenues:
  - retrait du fallback `legacy` dans `automaton_engine`;
  - retrait de `simplify_iexpr` des callsites encore actifs;
  - suppression des modules:
    - `automaton_bdd`,
    - `automaton_residual`,
    - `ltl_norm`,
    - `ltl_progress`;
  - simplification de la facade `Automaton_core` pour n'exposer que les outils
    encore utiles au pipeline Spot.
- Fichiers touches:
  - `lib_v2/runtime/middle_end/automaton_engine.ml`
  - `lib_v2/runtime/middle_end/automaton_engine.mli`
  - `lib_v2/runtime/middle_end/automata_core/automaton_core.ml`
  - `lib_v2/runtime/middle_end/automata_core/automaton_core.mli`
  - `lib_v2/runtime/middle_end/automata_core/automaton_guard.ml`
  - `lib_v2/runtime/middle_end/product/product_build.ml`
  - `lib_v2/runtime/middle_end/product/product_debug.ml`
  - `lib_v2/runtime/core/logic/ltl/ltl_valuation.ml`
  - `lib_v2/runtime/core/logic/ltl/ltl_valuation.mli`
  - `lib_v2/runtime/dune`

### Validation
- `opam exec -- dune build` : succes.
- `rg` sur `lib_v2/runtime` ne trouve plus de references a:
  - `Automaton_bdd`,
  - `Automaton_residual`,
  - `Ltl_norm`,
  - `Ltl_progress`,
  - `simplify_iexpr`,
  - `KAIROS_AUTOMATON_BACKEND`,
  - `Legacy_engine`.

### Sujet
Reduction de la plomberie maison JSON/LSP.

### Tentative 1 (scope maximal ecarte)
- Objectif: remplacer en une fois toute la serialisation JSON du protocole IDE et
  l'ensemble des objets LSP maison par des deriveurs et `Lsp.Types`.
- Resultat: ecarte pour cette iteration.
- Cause:
  - le protocole IDE interne a une forme legacy deja consommee cote client;
  - un basculement complet en une seule passe augmentait trop le risque de
    regressions de compatibilite.

### Tentative 2 (succes)
- Objectif: supprimer d'abord la plomberie la plus couteuse sans changer les
  surfaces metier.
- Resultat: succes.
- Choix retenus:
  - remplacement du JSON concatene a la main dans `ast_dump.ml` par une
    construction `Yojson.Safe.t`;
  - remplacement du transport JSON-RPC manuel de `kairos_lsp.ml` par
    `Jsonrpc`/`Lsp.Io`;
  - utilisation de `Lsp.Types` pour:
    - `initialize`,
    - `publishDiagnostics`,
    - les `Range`,
    - les `Location`/`SymbolInformation` utilises dans les reponses standard.
- Fichiers touches:
  - `lib_v2/runtime/frontend/parse/ast_dump.ml`
  - `bin/lsp/kairos_lsp.ml`
  - `bin/lsp/dune`
  - `lib_v2/runtime/dune`
  - `protocol/dune`
  - `kairos.opam`

### Validation
- `opam exec -- dune build` : succes.
- smoke test LSP:
  - envoi de `initialize`, `shutdown`, `exit` au binaire `kairos_lsp`;
  - reponses JSON-RPC valides recues;
  - code de sortie `0`.

### Nettoyage complementaire
- Suppressions effectives apres verification des usages:
  - fonction morte `path_of_uri` dans `bin/lsp/kairos_lsp.ml`;
  - reexport inutile `get_param_obj` dans `bin/lsp/kairos_lsp.ml`;
  - exposition publique inutile de `get_param_obj` dans `lib_v2/runtime/pipeline/lsp_app.mli`;
  - dependance/preprocess `ppx_deriving_yojson` retirees de:
    - `kairos.opam`,
    - `protocol/dune`,
    - `lib_v2/runtime/dune`.
- Motif:
  - le refactor retenu n'utilise finalement pas le deriveur JSON dans ces
    cibles; le garder aurait laisse une dependance morte.

### Sujet
Migration du backend de generation d'automates de surete vers Spot dans
`kairos-dev`, en preservant l'etat `bad` explicite attendu par le produit et
l'instrumentation.

### Tentative 1 (echec conceptuel)
- Objectif: utiliser directement la sortie moniteur deterministe de Spot
  (`ltl2tgba -M -D`) comme remplacement du compilateur residuel.
- Resultat: echec conceptuel.
- Cause:
  - la sortie moniteur peut rester incomplete;
  - en cas de violation, Spot signale surtout une absence de continuation,
    alors que Kairos attend un etat `bad` explicite detecte par `LFalse`.

### Tentative 2 (succes)
- Objectif: adapter la sortie Spot sans modifier le reste du pipeline.
- Resultat: succes.
- Choix retenus:
  - verification explicite du fragment safety via `ltlfilt --safety`;
  - generation HOA via `ltl2tgba -M -D -C -H`;
  - import HOA vers les gardes DNF de Kairos;
  - repli de toute region rejetante Spot vers un unique etat `bad` interne avec
    boucle `true`, afin de conserver la convention `first_false_idx`.
- Fichiers touches:
  - `lib_v2/runtime/middle_end/spot_automaton.ml`
  - `lib_v2/runtime/middle_end/automaton_engine.ml`
  - `lib_v2/runtime/middle_end/automaton_engine.mli`
  - `lib_v2/runtime/dune`

### Compatibilite / risques residuels
- Le moteur public `Automaton_engine` reste stable.
- Un mode de comparaison subsiste via `KAIROS_AUTOMATON_BACKEND=legacy`.
- Les etats acceptants importes depuis Spot sont volontairement abstraits
  (`LTrue`) : le pipeline n'utilise semantiquement que la detection de `bad`,
  mais les etiquettes DOT deviennent moins informatives qu'avec les formules
  residuelles maison.

### Validation
- `opam exec -- dune build` : succes.
- `_build/default/bin/cli/main.exe --log-level=quiet --dump-obc=- tests/ok/inputs/resettable_delay.kairos` : succes.
- `_build/default/bin/cli/main.exe --log-level=quiet --dump-product=- tests/ok/inputs/credit_balance_monitor.kairos` : succes.
- `_build/default/bin/cli/main.exe --log-level=quiet --dump-dot=- tests/ok/inputs/delay_int.kairos` : succes hors sandbox
  (le chemin DOT cree un fichier temporaire via `bos`).

### Sujet
Ajout d'un backend de simplification FO appuye sur Z3 pour les formules avec
symboles non interpretes.

### Tentative 1 (idee ecartee)
- Objectif: demander a Z3 une formule "simplifiee" complete et la reparser dans
  l'AST Kairos.
- Resultat: ecarte.
- Cause:
  - cout de reconstruction d'AST non justifie;
  - risque de produire des formes moins stables que les formes attendues par les
    passes Kairos;
  - complexite supplementaire pour typer et reparser proprement les termes.

### Tentative 2 (succes)
- Objectif: utiliser Z3 uniquement comme oracle de decision pour simplifier les
  formules sans changer le vocabulaire AST.
- Resultat: succes.
- Choix retenus:
  - nouveau module `lib_v2/runtime/core/logic/fo/fo_simplifier.ml`;
  - traduction SMT-LIB de `fo`, `iexpr`, `FPred` et `pre_k`;
  - requetes limitees a:
    - validite,
    - contradiction,
    - implication entre sous-formules;
  - simplification restreinte a des replis stables:
    - `true` / `false`,
    - suppression de conjuncts/disjuncts redondants,
    - repli d'une implication triviale.
- Integration:
  - affichage OBC via `obc_emit.ml`;
  - gardes du produit via `product_build.ml`.

### Compatibilite / risques residuels
- Si Z3 n'est pas trouvable, le module retombe sur les simplifications locales
  seulement.
- Les declarations SMT de predicates non interpretes supposent actuellement des
  arguments `Int` lorsqu'aucune information de type n'est recoverable dans la
  formule. C'est acceptable pour les usages actuels, mais a raffiner si des
  predicates booleens plus riches apparaissent.

### Validation
- `opam exec -- dune build` : succes.
- `_build/default/bin/cli/main.exe --log-level=quiet --dump-obc=- tests/ok/inputs/delay_int.kairos` : succes.
- `_build/default/bin/cli/main.exe --log-level=quiet --dump-obc=- tests/ok/inputs/resettable_delay.kairos` : succes.
- `_build/default/bin/cli/main.exe --log-level=quiet --dump-product=- tests/ok/inputs/credit_balance_monitor.kairos` : succes.

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

## 2026-03-08 — Théorèmes de complétude relative dans le noyau Rocq

- Objectif :
  - ajouter au noyau Rocq, en plus du théorème principal de correction, les
    trois résultats complémentaires discutés pendant l’audit :
    complétude relative de `NoBad`, validité relative des triples de support
    automate, et validité relative des triples d’invariant utilisateur.

- Refactoring du noyau :
  - [`rocq/KairosOracle.v`](/Users/fredericdabrowski/Repos/kairos/rocq/KairosOracle.v)
    - introduction de `TripleValidOnAdmissibleRuns` pour raisonner directement
      sur les runs admissibles du modèle ;
    - correction de `GeneratedBy` et `GeneratedTripleBy` pour que les clauses
      et triples `NoBad` ne soient générés que pour les pas réellement
      dangereux (`product_step_is_bad_target`) ;
    - ajout des hypothèses structurées
      `globally_correct`, `support_true_on_admissible_runs`,
      `support_exact_on_admissible_runs`,
      `node_invariants_true_on_admissible_runs` ;
    - ajout des trois théorèmes :
      - `relative_completeness_no_bad`,
      - `relative_completeness_automaton_support`,
      - `relative_completeness_user_invariant`.

- Réparations de structure :
  - [`rocq/path/Step2GeneratedClauses.v`](/Users/fredericdabrowski/Repos/kairos/rocq/path/Step2GeneratedClauses.v)
    - suppression de la référence morte à `gen_from_product_step` ;
    - exposition de `init_generated_items` à la place, pour rester cohérent
      avec l’API clause-centric actuelle.

- Observations :
  - la mise au point a mis en évidence un décalage réel : l’ancienne
    génération `NoBad` couvrait encore tous les pas bien formés, alors que
    l’intention de preuve et l’implémentation ne visent que les pas dangereux ;
  - ce point est maintenant corrigé dans le noyau.

- Validation :
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` : OK.
  - `opam exec --switch=5.4.1+options -- dune build` : OK.

## 2026-03-08 (suite) — Cohérence automate internalisée dans le noyau Rocq

- Objectif :
  - supprimer la formule abstraite `support_automaton_fo` du noyau Rocq ;
  - utiliser directement une notion sémantique de cohérence automate fondée sur
    l’état produit courant réel du run ;
  - réaligner la complétude relative, l’audit d’intention et le papier.

- Modifications principales :
  - [`rocq/KairosOracle.v`](/Users/fredericdabrowski/Repos/kairos/rocq/KairosOracle.v)
    - enrichissement de `StepCtx` avec les états courant/suivant des automates
      `A` et `G` ;
    - introduction de `coherence_current` et `coherence_next` comme propriétés
      sémantiques directes du contexte ;
    - suppression de `support_automaton_fo`,
      `support_true_on_admissible_runs` et
      `support_exact_on_admissible_runs` ;
    - réécriture des clauses et triples de cohérence/sécurité pour utiliser
      directement `coherence_current` ;
    - théorème `relative_completeness_automaton_support` prouvé désormais sans
      hypothèse additionnelle sur un support abstrait.
  - [`rocq/KairosModularIntegration.v`](/Users/fredericdabrowski/Repos/kairos/rocq/KairosModularIntegration.v)
    - réalignement des types et applications après le changement de signature
      exportée de `StepCtx` et `ctx_at` ;
    - suppression de la dépendance résiduelle à `support_automaton_fo`.
  - [`rocq/instances/DelayIntInstance.v`](/Users/fredericdabrowski/Repos/kairos/rocq/instances/DelayIntInstance.v)
    - mise à jour des usages de `StepCtx` et `ctx_at`.
  - [`rocq/INTENDED_THEOREM_AUDIT.md`](/Users/fredericdabrowski/Repos/kairos/rocq/INTENDED_THEOREM_AUDIT.md)
    et [`rocq/proof_architecture.md`](/Users/fredericdabrowski/Repos/kairos/rocq/proof_architecture.md)
    - vocabulaire stabilisé autour de `coherence` ;
    - retrait des formulations obsolètes faisant encore intervenir des helpers
      ou un support automate abstrait.
  - [`spec/rocq_oracle_model.tex`](/Users/fredericdabrowski/Repos/kairos/spec/rocq_oracle_model.tex)
    - correction des théorèmes de complétude relative pour refléter la nouvelle
      situation : la cohérence automate est maintenant interne au noyau ;
    - remplacement des dernières occurrences de `helper` par `coherence`.

- Observations :
  - le point délicat du proof engineering était localisé dans la preuve de
    `relative_completeness_automaton_support` ; le fond du raisonnement ne
    change pas, seule l’orientation/réduction de quelques égalités Rocq
    devait être ajustée ;
  - le vrai écart conceptuel n’était pas Why3, mais l’abstraction laissée dans
    `support_automaton_fo` ; il est désormais supprimé du noyau principal.

- Validation :
  - `opam exec --switch=5.4.1+options -- make -f rocq_build.mk -j2` : OK.
  - `opam exec --switch=5.4.1+options -- dune build` : OK.
  - `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` : OK.

- Complétude relative globale :
  - ajout dans [`rocq/KairosOracle.v`](/Users/fredericdabrowski/Repos/kairos/rocq/KairosOracle.v)
    du théorème de synthèse
    `relative_completeness_generated_triples` ;
  - ce théorème assemble désormais les trois familles déjà prouvées
    (`NoBad`, `AutomatonSupport`, `UserInvariant`) et donne enfin :
    “tout triple généré est valide sur les runs admissibles” sous les bonnes
    hypothèses ;
  - le papier a été mis à jour avec un énoncé et une preuve de synthèse
    correspondants.

## 2026-03-08 (suite) — Intégration Rocq native dans Dune

- Objectif :
  - arrêter de compiler Rocq via `rocq makefile` + `make`;
  - intégrer le développement dans le `dune-project`, sur le modèle de
    `tempo-kernel`.

- Réalisation :
  - ajout de [`rocq/dune`](/Users/fredericdabrowski/Repos/kairos/rocq/dune)
    avec une vraie théorie `rocq.theory` nommée `Kairos` ;
  - correction du `dune` racine pour inclure `rocq/` dans les répertoires
    pilotés par Dune ;
  - ajout de `rocq` dans [`kairos.opam`](/Users/fredericdabrowski/Repos/kairos/kairos.opam) ;
  - namespacing des `Require Import` Rocq vers `From Kairos ...` pour rendre la
    théorie buildable nativement sous Dune ;
  - nettoyage des anciens artefacts Rocq générés à la main (`.glob`, `.vo`,
    `.aux`) qui bloquaient la génération Dune.

- Validation :
  - `opam exec --switch=5.4.1+options -- dune build` : OK, y compris la partie Rocq.
  - le build manuel `rocq_build.mk` n’est plus nécessaire comme chemin
    principal de compilation.

- Retombée documentaire :
  - [`spec/rocq_oracle_model.tex`](/Users/fredericdabrowski/Repos/kairos/spec/rocq_oracle_model.tex)
    expose maintenant explicitement les trois résultats de complétude relative :
    - `NoBad`,
    - support automate,
    - invariant utilisateur ;
  - la présentation précise aussi que les clauses et triples `NoBad` ne sont
    générés que pour les pas dangereux, alors que les helpers restent générés
    sur les pas bien formés ;
  - PDF recompilé avec
    `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex` : OK.

## 2026-03-08
- Renforcement de l'introduction et du related work du papier Rocq : ancrage explicite aux notions classiques de safety sur traces infinies, logique temporelle lin'eaire, logique de Hoare et fondations du synchrone, avec ajout de r'ef'erences de fondation (Alpern/Schneider, Pnueli, Hoare, Cook, Halbwachs, Benveniste/Berry).
## 2026-03-08
- Abstract wording refined in `spec/rocq_oracle_model.tex`: removed an overly specific sentence about backend grouping/encoding/solver interaction and replaced it with a more abstract statement that concrete validation backends are later refinements of the mathematical core.
## 2026-03-08
- Figure layout pass on `spec/rocq_oracle_model.tex` after visual feedback: tightened label style, replaced long complement labels in the guarantee automaton with pedagogical `otherwise` labels explained in prose, and increased spacing in the relevant product subgraph to avoid node/label overlap.
- Added `specv2/guide.md`: a dedicated guide for rewriting the current paper toward a POPL-oriented version, with a principle-centric positioning, section-by-section rewrite guidance, theorem focus, terminology constraints, and related-work strategy.

## 2026-03-08
- Added a new positive Kairos example to [`tests/ok/inputs/credit_balance_monitor.kairos`](/Users/fredericdabrowski/Repos/kairos/tests/ok/inputs/credit_balance_monitor.kairos).
- Purpose of the example:
  - provide a more arithmetic and genuinely non-finite-state benchmark than `resettable_delay`;
  - keep a small control-state structure while relying on an unbounded integer memory.
- Retained formulation:
  - node-level assumptions only constrain booleans and non-negativity;
  - the balance-side admissibility condition is encoded in transition guards;
  - the key invariant in state `Run` is `m >= 0 /\ m = prev bal`.
- Reason for this formulation:
  - a stronger contract written directly with arithmetic on `prev bal` does not fit the current accepted surface syntax cleanly;
  - the guard-based version is accepted and proved by the current toolchain.
- Validation command used:
  - `DUNE_BUILD_DIR=/Users/fredericdabrowski/Repos/kairos/specv2/.kairos_build_credit_test opam exec -- dune exec -- kairos --log-level quiet --prove --prover-cmd /Users/fredericdabrowski/.opam/5.4.1+options/bin/z3 /Users/fredericdabrowski/Repos/kairos/tests/ok/inputs/credit_balance_monitor.kairos`
- Validation result:
  - command exits successfully;
  - only benign generated-code warnings about unused variables were reported.
## 2026-03-09

### Objectif

Rendre les exports DOT des automates `assume` et `guarantee` plus lisibles
pour l'exemple `resettable_delay`, en evitant l'inlining integral des gardes
sur les transitions.

### Tentatives et observations

- Observation: les exports separés `assume_automaton_dot` et
  `guarantee_automaton_dot` montraient initialement les residus comme labels de
  noeuds et des gardes completement inlines, ce qui rendait la lecture trop
  lourde.
- Succes: les noeuds des automates exportes sont maintenant etiquetes par des
  identifiants courts (`A0`, `A1`, `G0`, etc.) au lieu des formules
  residuelles.
- Succes: les gardes des transitions sont maintenant rendus avec des alias
  d'atomes `phi_i` au lieu des formules completement inlines.
- Succes: chaque graphe exporte embarque une legende en bas de figure qui
  rappelle la definition des `phi_i`.
- Succes: la reécriture des variables d'historique affiche `pre(x)` et
  `pre(reset)` dans la legende.

### Resultat

Les exports DOT/PDF `assume` et `guarantee` produits par Kairos sont maintenant
beaucoup plus proches de la presentation souhaitee pour le papier: graphe
compact, transitions nommees par atomes, definitions en legende.

## 2026-03-09

### Objectif

Remplacer les alias anonymes `phi_i` par des noms semantiques intermediaires
plus proches de l'usage papier pour l'exemple `resettable_delay`.

### Tentatives et observations

- Observation: la vue compacte precedente supprimait bien les residus et
  dechargeait les transitions, mais `phi_1`, `phi_2`, etc. restaient trop
  opaques.
- Succes: introduction d'un choix d'alias semantiques stables pour les
  predicats reconnus dans les gardes de l'exemple, par exemple
  `phi_rst`, `phi_nrst`, `phi_y0`, `phi_delay`, `phi_prev_rst`,
  `phi_prev_nrst`.
- Succes: regeneration des DOT/PDF via `kairos_lsp.exe` pour verifier le rendu
  final et la legende embarquee.

### Resultat

Les automates exportes affichent maintenant des noms de predicats
intermediaires lisibles, sans revenir au niveau complet des clauses
`A/G1/G2/G3`, ce qui correspond mieux a un usage de papier.

## 2026-03-09

### Objectif

Rapprocher visuellement les exports DOT `assume/guarantee` du rendu du papier,
avec une palette de couleurs, un etat initial mis en valeur, un etat `bad`
rouge, et une legende plus lisible.

### Tentatives et observations

- Succes: ajout d'un style DOT dedie dans `product_debug.ml` pour les automates
  separes, avec palettes distinctes `assumption/guarantee`.
- Succes: l'etat initial est maintenant visuellement distingue, et l'etat
  `false` est colore en rouge comme etat `bad`.
- Succes: les arcs qui menent a l'etat `bad` sont eux aussi rouges.
- Succes: la legende embarquee est maintenant stylisee avec un fond leger et
  une bordure coherente avec la palette du graphe.

### Resultat

Les PDF `assume` et `guarantee` produits par Kairos sont maintenant beaucoup
plus proches du rendu du papier et peuvent servir de base visuelle de
reference.

## 2026-03-09

### Objectif

Simplifier les gardes d'automates au niveau du pipeline Kairos lui-meme, pas
seulement dans le rendu DOT, afin que les obligations et le produit explicite
beneficient eux aussi de formules plus simples.

### Tentatives et observations

- Succes: extension de `simplify_iexpr` dans
  `lib_v2/runtime/core/logic/ltl/ltl_valuation.ml` pour eliminer certaines
  redondances simples sur les tests d'egalite/inegalite, par exemple
  `x = c ∧ x ≠ d` lorsque `c` et `d` sont distincts.
- Succes: branchement de cette simplification apres inlining des atomes dans
  `lib_v2/runtime/middle_end/automata_generation/automata_atoms.ml`, ce qui
  place la simplification au bon niveau de la chaine.
- Observation: cette premiere passe supprime bien des redondances evidentes
  comme `reset = 0 and not reset = 1`, mais elle ne fait pas encore de
  simplification dependante d'un domaine fini explicite.

### Resultat

Les gardes recuperes depuis l'automate sont maintenant simplifies avant d'etre
reutilises par le produit, les obligations et les vues DOT. Les sorties
`resettable_delay` montrent deja une nette reduction des redondances.

## 2026-03-09

### Objectif

Renforcer la simplification des gardes d'automates au niveau des clauses de
comparaison, afin de reduire aussi certaines disjonctions redondantes dans les
exports `assume/guarantee`.

### Tentatives et observations

- Echec partiel: une premiere passe locale sur les litteraux ne suffisait pas
  pour eliminer des formes du type `reset <> 1 or y = 0 or reset = 0`, car le
  probleme venait de l'implication entre clauses et non d'une contradiction
  syntactique immediate.
- Succes: ajout d'une normalisation des clauses de comparaisons dans
  `lib_v2/runtime/core/logic/ltl/ltl_valuation.ml`, avec suppression des
  inegalites rendues inutiles par une egalite deja presente dans la meme
  clause.
- Succes: ajout d'un test d'implication entre clauses normalisees pour
  eliminer certains disjoints plus forts que d'autres dans une DNF.
- Succes: la formule de garde `reset <> 1 or y = 0 or reset = 0` est maintenant
  simplifiee en `y = 0 or reset = 0` dans l'automate de garantie genere pour
  `resettable_delay`.
- Observation: des gardes plus volumineux subsistent encore, notamment dans
  `phi_1` et `phi_5` de l'automate de garantie; ils sont mieux simplifies
  qu'avant mais pas encore minimaux.

### Resultat

La simplification appliquee au niveau du programme Kairos reduit maintenant
non seulement des conjonctions redondantes, mais aussi une partie des
redondances entre clauses d'une disjonction. Les PDF/DOT regeneres pour
`resettable_delay` refletent cette amelioration.

## 2026-03-09

### Objectif

Clarifier l'architecture de simplification des formules autour des automates,
en fixant un point unique pour la recuperation des gardes apres
propositionnalisation et apres reinjection des atomes.

### Tentatives et observations

- Observation: la simplification etait jusqu'ici repartie entre
  `Automaton_guard.guard_to_iexpr`, `inline_atoms_iexpr`, puis plusieurs
  reapparitions manuelles de la meme sequence dans le produit, le debug DOT et
  l'instrumentation.
- Succes: ajout dans `automata_atoms.ml` de deux fonctions canoniques,
  `recover_guard_iexpr` et `recover_guard_fo`, qui incarnent explicitement
  l'etape "automate propositionnel -> garde sur formules programme".
- Succes: bascule des principaux consommateurs (`product_build.ml`,
  `product_debug.ml`, `instrumentation.ml`) sur cette API commune.
- Observation: cette centralisation ne change pas la separation
  `programme/assume/guarantee` dans la construction du produit; elle ne fait
  que fixer le bon niveau ou appliquer la simplification des gardes recuperes.

### Resultat

L'architecture de simplification est plus nette: la simplification
propositionnelle reste au niveau des gardes d'automates, et la simplification
apres reinjection des atomes se fait maintenant a un point unique reutilise par
le produit, l'instrumentation et les exports DOT.

## 2026-03-09

### Objectif

Aligner plus explicitement le niveau de normalisation utilise dans la
construction du produit avec celui deja retenu pour la recuperation des gardes
d'automates.

### Tentatives et observations

- Succes: `program_guard_fo` dans `product_build.ml` simplifie maintenant les
  gardes programme avant conversion en formule du premier ordre.
- Succes: la documentation locale de `fo_overlap_conservative` explicite que ce
  test travaille sur des gardes deja normalises et qu'il ne fusionne pas les
  composantes `programme/assume/guarantee`.
- Observation: cette clarification d'architecture ne change pas le rendu de
  `phi_1` et `phi_5` dans l'exemple `resettable_delay`; ces deux gardes
  demanderaient une minimisation logique plus forte que la normalisation
  actuellement en place.

### Resultat

Le pipeline est plus coherent: les gardes compares dans le produit sont
normalises au meme niveau que les gardes recuperes depuis les automates, tout
en conservant la separation conceptuelle entre les trois composantes du
produit.

## 2026-03-09

### Objectif

Renforcer la minimisation des DNF recuperees afin de simplifier davantage les
gardes residuels encore lourds, en particulier `phi_1` et `phi_5` de l'exemple
`resettable_delay`.

### Tentatives et observations

- Observation: les simplifications precedentes ne reconnaissaient comme
  litteraux de clause que des comparaisons de la forme `var = constante` ou
  `var <> constante`. Cela ne suffisait pas pour fusionner des clauses
  impliquant `y = pre(x)` ou `pre(reset) = 0`.
- Succes: generalisation de la fusion de clauses a des egalites/inegalites
  arbitraires entre termes `iexpr`, en traitant `pre(...)` comme un symbole non
  interprete.
- Succes: cette passe permet maintenant de fusionner des clauses qui ne
  differaient que par un litteral complementaire du type
  `pre(reset) = 0` / `pre(reset) <> 0`.
- Succes: `phi_1` de l'automate de garantie est plus court qu'avant; deux
  clauses intermediaires ont ete absorbees en une clause plus generale.
- Observation: `phi_5` reste essentiellement inchange. Sa reduction demanderait
  soit une minimisation propositionnelle plus agressive, soit des hypotheses de
  domaine supplementaires qui ne sont pas introduites ici.

### Resultat

La minimisation des gardes recuperes ne se limite plus aux comparaisons
`variable/constante`. Elle sait maintenant raisonner sur des termes comme
`pre(x)` de facon purement syntaxique, ce qui simplifie effectivement une
partie du graphe de garantie tout en restant compatible avec le cadre abstrait
de Kairos.

## 2026-03-09

### Objectif

Ameliorer le rendu DOT des automates separes en evitant d'introduire un alias
`phi_k` pour les gardes trivialement vraies, en particulier sur les boucles de
l'etat `bad`.

### Tentatives et observations

- Succes: le rendu dans `product_debug.ml` affiche maintenant `⊤` directement
  lorsqu'une transition a pour garde `true`.
- Succes: ces gardes triviales sont exclues de la legende des `phi_k`, qui ne
  conserve plus que les formules non triviales.
- Observation: cela ne change pas l'automate lui-meme, seulement son rendu; les
  boucles `bad -> bad` restent bien totalisees par `true`.

### Resultat

Les PDF `assume` et `guarantee` affichent maintenant `⊤` sur les boucles
triviales de l'etat `bad`, ce qui est plus naturel et plus proche du niveau de
lecture vise pour un papier.

## 2026-03-09

### Objectif

Donner aux exports DOT `assume/guarantee` un rendu plus mathematique pour les
labels de noeuds, les alias `phi_i`, et les formules de la legende.

### Tentatives et observations

- Succes: les noeuds des automates separes utilisent maintenant des labels de
  type `A_i`, `G_i`, `A_bad`, `G_bad` avec vrais sous-indices via labels HTML
  Graphviz.
- Succes: les aliases de transition sont maintenant rendus en `φᵢ` plutot qu'en
  `phi_i`.
- Succes: la legende remplace les operateurs textuels par des notations
  usuelles (`¬`, `∧`, `∨`, `≠`, `⊤`, `⊥`).
- Observation: cette passe repose sur le rendu HTML/Unicode effectivement
  supporte par Graphviz dans le backend PDF, plutot que sur une hypothese plus
  fragile de support direct du LaTeX math.

### Resultat

Les PDF Kairos se rapprochent maintenant davantage du style d'un papier:
notation des etats plus propre, `φᵢ` sur les arcs, et legende plus compacte et
mathematique.

## 2026-03-09

### Objectif

Ameliorer la lisibilite des aliases `φᵢ` sur les arcs, en les eloignant
davantage des segments pour que les sous-indices restent visibles.

### Tentatives et observations

- Succes: augmentation de `labeldistance` et `labelangle` dans le style `edge`
  du DOT genere par `product_debug.ml`.
- Observation: cette retouche ne modifie pas le contenu du graphe, seulement la
  mise en page des labels d'arcs dans le PDF Graphviz.

### Resultat

Les labels `φᵢ` sont maintenant places plus loin des arcs, ce qui ameliore la
lecture des sous-indices dans les PDF exportes.

## 2026-03-09

### Objectif

Supprimer le recouvrement residuel entre labels d'arcs et arêtes dans les PDF
Graphviz, et produire egalement le PDF de l'automate produit.

### Tentatives et observations

- Observation: augmenter seulement `labeldistance` et `labelangle` ne suffisait
  pas toujours; Graphviz laissait encore certains labels trop proches du trace
  de l'arête.
- Succes: passage des labels d'arcs du mode `label=` au mode `xlabel=` dans les
  automates separes et dans le graphe produit, avec `forcelabels=true`.
- Succes: generation explicite du DOT/PDF du produit pour `resettable_delay`.

### Resultat

Les labels d'arcs sont maintenant confies au placement externe de Graphviz,
ce qui reduit fortement le recouvrement avec les arêtes. Les trois PDF
`assume`, `guarantee` et `product` sont maintenant exportes.

## 2026-03-09

### Objectif

Appliquer au graphe produit le meme niveau d'amelioration visuelle que celui
obtenu sur les automates separes.

### Tentatives et observations

- Succes: les etats du produit utilisent maintenant une notation plus lisible,
  avec `A₀`, `G₂`, `A_bad`, `G_bad` dans les tuples d'etat.
- Succes: la coloration des noeuds distingue l'etat initial, les etats avec
  garantie violee, et les etats avec hypothese violee.
- Succes: les labels d'arcs du produit passent eux aussi par `xlabel`, avec
  references lisibles du type `A[A₀ → A_bad]` et `G[G₂ → G_bad]`.
- Succes: suppression des doublons strictement identiques au niveau du rendu
  DOT, pour alleger le graphe produit sans changer son contenu semantique.

### Resultat

Le PDF du produit est maintenant coheremment stylise avec les automates
`assume/guarantee`: meme logique de notation, meilleure separation visuelle des
classes d'etats, et rendu plus propre des transitions.

## 2026-03-09

### Objectif

Simplifier le nommage des noeuds du produit en supprimant le nom du programme
dans les labels de noeuds, au profit d'une numerotation courte `P_i`.

### Tentatives et observations

- Succes: les noeuds du produit sont maintenant etiquetes `P₀`, `P₁`, ... en
  premiere ligne, avec le triple d'etats source conserve en seconde ligne.
- Observation: cela allege le rendu sans perdre l'information structurante,
  puisque le triple `(prog, A_j, G_k)` reste visible dans chaque noeud.

### Resultat

Le graphe produit est plus compact et plus lisible: les noeuds sont identifies
par une numerotation courte `P_i`, tout en conservant explicitement leur
decomposition en etat programme et etats d'automates source.

## 2026-03-09

### Objectif

Retirer la plomberie JSON manuelle restante autour du serveur LSP et du
protocole IDE, sans casser les clients existants.

### Tentatives et observations

- Succes: le serveur LSP passe maintenant par `jsonrpc` et `lsp` pour le
  framing JSON-RPC, les requetes/reponses standard et les types LSP usuels.
- Succes: `ast_dump.ml` construit des valeurs `Yojson.Safe.t` au lieu de
  concatener du JSON a la main.
- Succes: `protocol/lsp_protocol.ml` utilise maintenant
  `ppx_deriving_yojson` pour les payloads IDE (`outputs`, `automata_outputs`,
  `goal_info`, etc.), avec des alias `yojson_of_*` conserves pour ne pas
  casser les appelants existants.
- Observation: le type `config` necessitait un decodeur manuel residuel pour
  conserver la compatibilite sur le champ optionnel `engine`, qui doit encore
  valoir `"v2"` par defaut quand il est absent.

### Resultat

Le transport LSP standard et les payloads IDE reposent maintenant sur des
bibliotheques / deriveurs, ce qui retire l'essentiel de la serialisation
manuelle fragile. Le reliquat volontaire est limite au comportement de
compatibilite sur `config.engine`.

## 2026-03-09

### Objectif

Poursuivre le nettoyage du serveur LSP en retirant les reponses standard et les
notifications Kairos encore construites ad hoc dans `kairos_lsp.ml`.

### Tentatives et observations

- Succes: les reponses standard `hover`, `definition`, `references`,
  `completion` et `formatting` passent maintenant par `Lsp.Types`.
- Succes: ajout de types partages dans `Lsp_protocol` pour
  `goalsReady`, `goalDone` et `outputsReady`, avec un identifiant JSON-RPC
  transporte par un type dedie `rpc_request_id`.
- Succes: le client IDE decode maintenant `goalsReady` et `goalDone` via
  `Lsp_protocol` au lieu de reparser les champs a la main.
- Observation: quelques morceaux restent volontairement en JSON brut dans
  `kairos_lsp.ml`, en particulier les notifications `$/progress`, certains
  payloads de requetes Kairos et les erreurs JSON-RPC atypiques, car le gain a
  ce stade serait faible par rapport au churn.

### Resultat

Le chemin critique serveur LSP <-> IDE est maintenant typé de bout en bout pour
les reponses standard les plus importantes et pour les notifications Kairos
principales. Le JSON artisanal restant est residuel et concentre dans quelques
helpers de glue.

## 2026-03-09

### Objectif

Aligner aussi le client IDE sur `jsonrpc` et `lsp`, afin d'eviter d'avoir un
 serveur modernise mais un client qui continue a reimplementer seul le
 framing JSON-RPC et les messages LSP standard.

### Tentatives et observations

- Succes: `ide_lsp_process_client.ml` utilise maintenant `Lsp.Io` et
  `Jsonrpc.Packet` pour lire/ecrire les paquets.
- Succes: les messages standard `initialize`, `didOpen`, `didChange`,
  `didSave`, `didClose`, `hover`, `references`, `completion`, `formatting` et
  `$/cancelRequest` passent maintenant par `Lsp.Types`.
- Succes: les reponses standard sont decodees via `Lsp.Types` pour `Hover`,
  `Location`, `CompletionItem`, `CompletionList` et `TextEdit`.
- Observation: il reste du JSON manuel dans le client pour les requetes Kairos
  specifiques (`outline`, `goalsTree*`, `run`, passes backend), ce qui est
  acceptable tant que leur schema n'est pas encore entierement decrit dans
  `Lsp_protocol`.

### Resultat

Le client et le serveur partagent maintenant la meme base technique pour le
transport JSON-RPC et pour une large partie des messages LSP standard. Le code
manuel restant dans le client est essentiellement limite aux API Kairos
specifiques et a quelques parseurs d'artefacts metier.

## 2026-03-09

### Objectif

Eliminer aussi le JSON manuel residuel du client IDE pour les requetes et
notifications Kairos specifiques.

### Tentatives et observations

- Succes: ajout dans `Lsp_protocol` des schemas partages pour:
  `outline`, `goalsTreeFinal`, `goalsTreePending`, `instrumentationPass`,
  `obcPass`, `whyPass`, `obligationsPass`, `evalPass`, `dotPngFromText`,
  ainsi que pour `outline_payload` et `goal_tree_node`.
- Succes: `ide_lsp_process_client.ml` utilise maintenant ces encodeurs pour les
  requetes Kairos et ces decodeurs pour `outline`, `goal tree` et les
  notifications `outputsReady`, `goalsReady`, `goalDone`.
- Succes: `ide_lsp_types` a ete aligne sur les types `outline_*` et
  `goal_tree_*` de `Lsp_protocol`, ce qui retire une duplication de schema.
- Observation: il reste encore un peu de glue JSON dans le client pour router
  les notifications par nom de methode et pour quelques resultats LSP sous
  forme de listes, mais le schema metier lui-meme n'est plus duplique.

### Resultat

Les payloads Kairos critiques sont maintenant decrits une seule fois dans
`Lsp_protocol` et reutilises des deux cotes. Le client IDE n'a plus de format
JSON metier "prive" pour ces appels.

## 2026-03-09

### Objectif

Corriger la regression introduite sur le chemin `prove` apres bascule des
requetes IDE vers `Lsp_protocol`.

### Tentatives et observations

- Observation: le client IDE envoyait bien `kairos/run` avec le schema
  `Lsp_protocol.config` (`input_file`, `timeout_s`, etc.), mais le serveur LSP
  lisait encore majoritairement les anciens champs camelCase (`inputFile`,
  `timeoutS`, ...).
- Echec constate: le serveur repondait `Missing valid inputFile` alors que le
  fichier existait, simplement parce que le decodeur legacy ne trouvait plus le
  champ.
- Succes: ajout d'un decodeur prioritaire via `Lsp_protocol` dans
  `kairos_lsp.ml` pour `run` et pour les autres requetes Kairos deja migrees,
  avec repli legacy seulement en fallback.

### Resultat

Le chemin `prove` redevient compatible avec le client IDE refactorise. Un smoke
test JSON-RPC sur `kairos/run` avec payload `snake_case` passe de nouveau.

## 2026-03-09

### Objectif

Simplifier la fenetre des automates de l'IDE: retirer l'onglet
d'instrumentation/diagnostic, exposer l'automate du programme au meme niveau
que `A`, `G` et le produit, et verifier que le theme par defaut reste clair.

### Tentatives et observations

- Observation: la fenetre `Automata` affichait deja les graphes `Guarantee`,
  `Assume` et `Product`, mais le texte de diagnostic restait expose dans un
  onglet separé alors qu'il ne sert plus comme vue principale.
- Succes: ajout du graphe `Program` dans le pipeline de sorties (`outputs`,
  `automata_outputs`, bridge LSP, backend IDE), puis branchement de cet automate
  dans la fenetre dediee.
- Succes: suppression de l'onglet de diagnostic dans `obcwhy3_ide.ml` tout en
  conservant le buffer interne pour les obligations/prunes, afin de ne pas
  perturber le reste du code UI pendant cette etape.
- Observation: `Ide_config.default_prefs` et `load_prefs` etaient deja
  correctement calibres sur le theme `light` par defaut; aucune surcouche ne
  rebasculait vers `dark` a l'ouverture.

### Resultat

La fenetre des automates presente maintenant uniquement les vues graphiques
`Program`, `Guarantee G`, `Assume A` et `Product`. Le theme par defaut reste
`light`.

## 2026-03-09

### Objectif

Rendre l'installation opam de `kairos` effectivement utilisable, avec les
binaires `kairos`, `kairos-lsp` et `kairos-ide` poses dans le switch.

### Tentatives et observations

- Echec constate: `opam` acceptait le pin puis marquait `kairos` comme
  installe, mais aucun binaire n'etait copie dans `~/.opam/5.4.1+options/bin`.
- Observation: `_build/default/kairos.install` contenait pourtant bien
  `bin/kairos`, `bin/kairos-lsp`, `bin/kairos-ide` et `bin/kairos_v2`.
- Cause racine identifiee: le fichier `kairos.opam` etait trop minimal. Il ne
  declarait ni etape `build` ni etape `install`, donc `opam` n'executait aucun
  `dune build @install` ni `dune install`; il enregistrait seulement l'etat du
  paquet.
- Succes: correction de `kairos.opam` avec:
  - `opam-version: "2.0"`;
  - dependance `rocq-prover` a la place de `rocq`;
  - retrait de la dependance erronee `ocamllex`;
  - ajout explicite des phases `build` et `install` via `dune`.

### Resultat

Le paquet opam est maintenant configure pour installer reellement les
executables et bibliotheques du depot lors d'un `opam reinstall kairos
--working-dir`.

## 2026-03-09

### Objectif

Corriger l'activation du plugin VS Code pour que les commandes `kairos.build`
et `kairos.prove` existent meme si le serveur LSP ne demarre pas.

### Tentatives et observations

- Echec constate: VS Code affichait `command 'kairos.build' not found` et
  `command 'kairos.prove' not found`.
- Cause racine identifiee: `activate()` attendait `client.start()` avant
  d'enregistrer les commandes. Si `kairos-lsp` etait indisponible dans
  l'environnement VS Code, l'activation avortait et aucune commande n'etait
  enregistree.
- Succes: demarrage du client LSP passe en tache asynchrone avec promesse
  memorisee; les commandes sont maintenant enregistrees immediatement et
  `ensureClientReady()` remonte une erreur explicite seulement au moment
  d'executer une action qui depend du serveur.

### Resultat

Le plugin reste chargeable et les commandes Kairos apparaissent correctement
dans VS Code, meme si la configuration du serveur LSP est invalide.

## 2026-03-09

### Objectif

Corriger le packaging `.vsix` pour que l'extension VS Code charge reellement
ses dependances runtime.

### Tentatives et observations

- Echec constate: malgre la correction de `activate()`, VS Code affichait
  toujours `command 'kairos.build' not found`.
- Cause racine identifiee: le script `scripts/vscode.sh --package` utilisait
  `vsce package --no-dependencies`. Le `.vsix` produit ne contenait donc pas
  `node_modules/vscode-languageclient`, et l'extension plantait avant son
  activation.
- Succes: retrait de `--no-dependencies` et increment de version du plugin pour
  forcer une vraie reinstallation cote VS Code.

### Resultat

Le `.vsix` regenere embarque maintenant les dependances runtime necessaires a
l'activation de l'extension.

## 2026-03-09

### Objectif

Stabiliser le demarrage du serveur LSP Kairos dans VS Code sur la machine
locale.

### Tentatives et observations

- Observation: `kairos-lsp` est correctement installe dans le switch opam:
  `/Users/fredericdabrowski/.opam/5.4.1+options/bin/kairos-lsp`.
- Cause probable du message `Kairos LSP failed to start`: VS Code ne charge pas
  necessairement le `PATH` du shell opam sur macOS.
- Succes: ajout d'un `settings.json` de workspace pointant directement vers le
  binaire absolu du switch opam.

### Resultat

Le demarrage du plugin ne depend plus du `PATH` herite par VS Code pour
trouver `kairos-lsp`.

### Ajustement

- Amelioration UX: remplacement du chemin absolu vers le binaire par une
  commande `opam exec -- kairos-lsp` dans le `settings.json` du workspace.
- Motivation: eviter de figer un chemin local ou un switch explicite, tout en
  conservant un lancement robuste du serveur depuis VS Code sur macOS.
- Observation complementaire: la vue `Automata` retombait en pratique sur
  l'affichage du texte DOT quand VS Code ne trouvait pas `dot` dans son
  environnement.
- Ajustement: `kairos.graphviz.dotPath` est fixe explicitement sur
  `/opt/homebrew/bin/dot` dans le workspace pour retrouver le rendu SVG colore
  attendu.
- Durcissement supplementaire: ajout d'un fallback interne dans l'extension
  pour resoudre `dot` via les chemins Homebrew/macOS usuels quand la commande
  configuree n'est pas executable depuis le processus VS Code.
- Correction de rendu: la vue `Automata` priorise maintenant une image PNG
  generee localement via Graphviz et encodee en data URI dans la webview,
  avec le SVG conserve pour export et fallback. Cela se rapproche davantage du
  rendu visuel de l'IDE native et evite les echecs d'integration SVG.
- Correction structurelle supplementaire: la vue `Automata` demande
  maintenant en priorite les PNG au serveur LSP via `kairos/dotPngFromText`,
  ce qui aligne le chemin de rendu sur celui deja utilise par l'IDE native.

## 2026-03-09

### Objectif

Supprimer le DOT du chemin UX VS Code et faire porter les rendus automates
directement par les sorties du backend/LSP.

### Tentatives et observations

- Observation: le LSP savait deja calculer des PNG arbitraires via
  `kairos/dotPngFromText`, mais les sorties `run` et `instrumentationPass`
  n'exposaient pas les PNG des quatre graphes.
- Limite architecturale constatee: l'extension recevait le DOT, puis devait le
  renvoyer au serveur uniquement pour retrouver une image. Ce detour etait
  inutile et fragile.
- Succes: ajout de `program_png`, `assume_automaton_png`,
  `guarantee_automaton_png` et `product_png` dans:
  - `Pipeline.outputs` et `Pipeline.automata_outputs`;
  - `Lsp_protocol.outputs` et `Lsp_protocol.automata_outputs`;
  - le mapping LSP (`lsp_app.ml`);
  - le client VS Code TypeScript.
- Succes: smoke test JSON-RPC sur `kairos/instrumentationPass` avec
  `tests/ok/inputs/resettable_delay.kairos`, confirmant la presence des quatre
  champs PNG dans la reponse.
- Succes: retrait du DOT des surfaces utilisateur VS Code:
  - plus de preview DOT dans `Automata`;
  - plus de commande `Kairos: Open DOT`;
  - plus d'artefact DOT visible dans la vue `Artifacts`.

### Resultat

Le backend expose maintenant nativement les images des quatre graphes et
l'extension VS Code consomme ces artefacts directement. Le DOT reste un format
d'export technique, mais n'est plus une surface de lecture dans l'UI VS Code.

## 2026-03-09

### Objectif

Remettre toutes les ouvertures Kairos dans le groupe d'onglets courant, sans
creation automatique d'une colonne laterale.

### Tentatives et observations

- Observation: plusieurs panneaux (`Automata`, `Proof Dashboard`, `Artifacts`,
  `Eval`, `Pipeline`, `Compare`) etaient crees avec `ViewColumn.Beside`, ce qui
  ouvrait une nouvelle colonne et masquait rapidement le code Kairos.
- Succes: remplacement de cette politique par un ciblage explicite du groupe
  d'editeur courant:
  - helper `preferredViewColumn()` pour les webviews;
  - helper `preferredEditorColumn()` pour `showTextDocument`.
- Succes: les ouvertures de Why, SMT dump, fichiers recents et panneaux Kairos
  se font maintenant dans la meme zone d'onglets que le fichier source actif.

### Resultat

L'UI Kairos n'impose plus de colonnes supplementaires par defaut; la lecture du
code source et des vues associees reste concentree dans le meme groupe
d'editeur.

## 2026-03-10

### Objectif

Ajouter un chemin "native solver unsat core" sur une VC Why3 ciblee, puis
l'exposer proprement en CLI, protocole et UI.

### Tentatives et observations

- Observation: le flux SMT Why3/Z3 standard ne portait ni assertions `:named`
  sur les hypotheses Kairos, ni `(get-unsat-core)`. Un core solveur natif
  n'etait donc pas recuperable tel quel.
- Succes: ajout d'un mode SMT specialise dans `why_prove.ml` avec:
  - `(set-option :produce-unsat-cores true)`;
  - assertions `hid_<n>` derivees des hypotheses Kairos instrumentees;
  - `(get-unsat-core)` en fin de script.
- Succes: ajout de `native_unsat_core_for_goal` dans le backend Why3:
  - ciblage par `goal_index`;
  - execution Z3 sur le SMT re-ecrit;
  - parsing du core;
  - remappage vers les `hid` Kairos.
- Succes: ajout de l'export CLI
  `--dump-native-unsat-core-json FILE --proof-trace-goal-index N`.
- Echec partiel utile: sur `tests/ok/inputs/delay_int.kairos`, le goal `0`
  retourne un core solveur natif valide, mais vide cote `hid`. Cela signifie
  que la contradiction est fermee par le contexte auxiliaire restant et non par
  les hypotheses Kairos nommees seules.
- Observation structurante: un unsat core solveur natif est exploitable pour
  une VC prouvee (`unsat`), pas pour un goal reellement en `failure`.
- Succes: exposition de bout en bout:
  - `native_unsat_core_solver`;
  - `native_unsat_core_hypothesis_ids`;
  - affichage `Native Unsat Core` dans `Explain Failure`.

### Validation

- Build sequentiel:
  - `opam exec -- dune build bin/cli/main.exe --display=short`
  - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
  - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - `npm run compile`
- Cas reels:
  - `delay_int.kairos`, `goal 0`:
    `--dump-native-unsat-core-json - --proof-trace-goal-index 0`
    -> core solveur Z3 recupere;
  - `delay_int.kairos`, `goal 0`:
    `--dump-proof-traces-json - --proof-trace-goal-index 0`
    -> trace standard enrichie avec methode `Native SMT unsat core...`;
  - `delay_int.kairos`, `goal 5`:
    `--dump-native-unsat-core-json - --proof-trace-goal-index 5`
    -> `null`, conforme a un goal non prouve.

### Resultat

Kairos dispose maintenant d'un chemin natif solveur pour les unsat cores
cibles, distinct du fallback par replay-minimization. La limite restante est
explicite: ce core depend d'une re-ecriture SMT guidee par les `hid`, et n'est
disponible que si le solveur repond effectivement `unsat`.

### Suite 2026-03-10: statuts d'echec fins et sonde contre-exemple

- Succes: ajout d'une sonde solveur native ciblee par goal dans `why_prove.ml`
  qui rejoue une VC via Z3 avec `produce-models`, `get-info :reason-unknown` et
  `get-model`.
- Succes: exposition CLI de cette sonde via
  `--dump-native-counterexample-json FILE --proof-trace-goal-index N`.
- Succes: le diagnostic transporte maintenant:
  - `solver_detail`;
  - `native_counterexample_solver`;
  - `native_counterexample_model`.
- Succes: l'UI `Explain Failure` affiche maintenant `Solver Detail` et
  `Native Counterexample`.
- Validation partielle:
  - `delay_int.kairos`, goal `5`: la sonde native est bien executable sur un
    goal failed cible, mais ne fournit pas encore de modele exploitable;
  - `constant_zero_invalid_model.kairos`: la sonde native confirme un cas
    `valid`, avec absence normale de modele.
- Echec restant: je n'ai pas encore extrait un cas `sat`/`invalid` valide dans
  la suite de tests actuelle pour montrer un vrai contre-exemple solveur
  remonte de bout en bout. La plomberie est la, mais la demonstration CLI
  "modele non trivial" reste a completer.

### Suite 2026-03-10: documentation d'installation

- Succes: ajout d'un guide `INSTALL.md` a la racine du depot.
- Contenu couvre:
  - installation via `opam`;
  - dependances Why3 / Z3 / Graphviz;
  - verification des binaires `kairos`, `kairos-lsp`, `kairos-ide`;
  - packaging et installation de la VSIX VS Code;
  - configuration recommandee du LSP dans VS Code;
  - verification finale et depannage courant.

### Suite 2026-03-10: correction affichage Automata VS Code

- Symptomes observes:
  - la vue `Kairos Automata` affichait un grand canevas gris;
  - les boutons et panneaux lateraux se rendaient, mais le statut `Renderer`
    restait vide;
  - le DOT ne devait plus etre visible ni utilise comme fallback utilisateur.
- Tentatives precedentes:
  - suppression complete du DOT de la surface UI et de l'etat extension;
  - activation de `generatePng: true` sur `kairos/instrumentationPass`;
  - ouverture CSP de la webview pour `img-src data:`.
- Analyse:
  - le backend/LSP renvoie bien `program_png`, `assume_automaton_png`,
    `guarantee_automaton_png` et `product_png`;
  - la cause la plus probable du panneau gris restant est l'injection inline de
    PNG volumineux dans le script webview via des `data:` URIs, ce qui rend le
    panneau fragile au runtime.
- Correction appliquee:
  - abandon du transport inline `data:image/png;base64,...` pour la vue
    `Kairos Automata`;
  - copie des PNG vers `globalStorage/automata/*.png` cote extension;
  - exposition a la webview via `webview.asWebviewUri(...)`;
  - declaration explicite de `localResourceRoots` pour les panneaux Automata et
    Compare;
  - regeneration de `kairos-vscode-0.1.2.vsix`.
- Validation:
  - `npm run compile` OK;
  - packaging `npx @vscode/vsce package` OK.
- Point de controle utilisateur attendu:
  - apres reinstallation/rechargement, la zone centrale de `Kairos Automata`
    doit afficher un `<img>` de graphe et `Renderer` doit indiquer
    `PNG renderer active`.

### Suite 2026-03-10: coloration syntaxique Kairos dans VS Code

- Constat initial:
  - l'extension declarait bien le langage `kairos` et son
    `language-configuration.json`;
  - aucune grammaire TextMate n'etait fournie, donc pas de vraie coloration
    syntaxique.
- Travail effectue:
  - audit des exemples reels `resettable_delay.kairos`, `delay_int.kairos`,
    `light_latch.kairos`, `delay_int2.kairos`, `handoff.kairos`;
  - ajout d'une grammaire `syntaxes/kairos.tmLanguage.json`;
  - declaration de cette grammaire dans `extensions/kairos-vscode/package.json`.
- Portee de la coloration:
  - sections DSL: `contracts`, `locals`, `states`, `invariants`, `transitions`;
  - en-tetes et declarations: `node`, `returns`, noms de noeuds, etats,
    variables declarees;
  - contrats et transitions: `requires`, `ensures`, `to`, `when`, `skip`, `end`;
  - operateurs temporels: `G`, `F`, `X`, `U`, `W`, `R`, `M`, `always`,
    `eventually`, `next`, `prev`, `prev2`, ...;
  - types, booleens, nombres, affectation `:=`, comparaisons, ponctuation;
  - commentaires `//` et `(* ... *)`.
- Validation:
  - parse JSON de la grammaire OK;
  - `npm run compile` OK;
  - `npx @vscode/vsce package` OK;
  - la VSIX contient bien `syntaxes/kairos.tmLanguage.json`.

### Suite 2026-03-10: correction du contexte actif Dashboard/Prove

- Symptome:
  - apres un `prove`, l'ouverture ou l'usage du Dashboard pouvait declencher
    `Open a .kairos or .obc file first` alors qu'un fichier Kairos etait bien
    ouvert et que les preuves venaient de passer.
- Cause:
  - plusieurs actions de l'extension supposaient que
    `vscode.window.activeTextEditor` restait le fichier `.kairos`;
  - une fois le focus passe sur un webview (`Dashboard`, `Explain Failure`,
    `Automata`), cette hypothese devient fausse.
- Correction:
  - remplacement du controle `ensureKairosEditor()` par une resolution de
    contexte plus robuste:
    - editeur actif Kairos si disponible;
    - sinon editeur visible Kairos;
    - sinon `state.activeFile` persiste et reouvert si necessaire.
  - application de ce correctif aux chemins:
    - `refreshOutlineFromActiveEditor`;
    - `openSourceLocation`;
    - `runWithOptions`;
    - `runAutomataPass`;
    - `runEval`;
    - `kairos.openOutlineLocation`.
- Validation:
  - `npm run compile` OK;
  - `npx @vscode/vsce package` OK.

### Suite 2026-03-10: durcissement du panneau Automata

- Observation utilisateur:
  - le panneau `Kairos Automata` continuait a montrer un grand fond gris,
    sans image ni message d'erreur exploitable.
- Hypothese technique:
  - le HTML statique se rend, mais le script d'initialisation webview ne termine
    pas toujours correctement, ce qui laissait la zone canvas muette.
- Correctif applique:
  - pre-rendu serveur du graphe `Program` dans le HTML initial;
  - pre-rendu initial du statut `Renderer`;
  - encapsulation de l'initialisation JS dans un `try/catch`;
  - remontée explicite des erreurs webview dans `Renderer`.
- Effet attendu:
  - meme en cas de panne JS cliente, un graphe `Program` ou au moins un message
    d'erreur apparait des l'ouverture, au lieu d'un panneau vide.

### Suite 2026-03-10: verrouillage de version VS Code

- Constat:
  - deux versions de l'extension Kairos etaient presentes dans
    `~/.vscode/extensions/`: `0.1.1` et `0.1.2`;
  - le message exact `Open a .kairos or .obc file first.` n'existe plus dans
    `0.1.2`, mais existe encore dans `0.1.1`.
- Risque:
  - ambiguite de cache/chargement cote VS Code pendant les iterations locales.
- Action:
  - increment de version vers `0.1.3` dans `package.json` et
    `package-lock.json`;
  - regeneration de la VSIX `kairos-vscode-0.1.3.vsix`.

### Suite 2026-03-10: dashboard VC et erreurs de rendu automata

- Symptome utilisateur:
  - le `Proof Dashboard` n'affichait pas correctement la colonne `VC`;
  - la vue `Automata` restait sur un rendu gris sans message explicite.
- Cause dashboard:
  - le tableau etait construit directement depuis `proof_traces`, alors que les
    identifiants `vcid` sont plus stables dans `goalsTree`.
- Correction dashboard:
  - reconstruction des lignes a partir de `goalsTree`;
  - enrichissement optionnel avec `proof_traces` pour conserver les diagnostics
    detailles;
  - fallback explicite sur `entry.vcid` quand `trace.vc_id` est absent.
- Cause automata:
  - l'absence d'image restait silencieuse lorsqu'un chemin PNG n'etait pas
    disponible, introuvable, ou non copiable vers le cache webview.
- Correction automata:
  - `getGraphAssets` remonte maintenant un `renderError` explicite par graphe:
    absence de chemin, fichier manquant, ou echec de copie.
- Validation:
  - `npm run compile` OK;
  - `npx @vscode/vsce package` OK.

### Suite 2026-03-10: ouverture Automata auto-alimentee

- Retour utilisateur:
  - `Renderer` signalait `No PNG path was returned by Kairos.`
- Interpretation:
  - le panneau `Automata` pouvait etre ouvert sans qu'aucun passage
    instrumentation n'ait encore peuple `state.automata` ou `state.outputs`
    avec des `*_png`.
- Correctif:
  - `showAutomataPanel()` verifie maintenant la presence d'au moins un PNG
    d'automate;
  - en l'absence de PNG, l'extension lance automatiquement
    `runAutomataPass()` au lieu d'ouvrir un panneau vide.
- Validation:
  - `npm run compile` OK;
  - `npx @vscode/vsce package` OK.

### Suite 2026-03-10: diagnostic backend Graphviz pour les PNG

- Cause structurelle identifiee:
  - le backend produisait les PNG via `Pipeline.dot_png_from_text` puis
    `Pipeline.graph_pngs`;
  - en cas d'echec `dot -Tpng`, ces fonctions retournaient simplement `None`,
    sans exposer `stderr` ni le motif de l'echec.
- Travail effectue:
  - ajout de `dot_png_from_text_diagnostic` dans `pipeline.ml`;
  - capture du statut de sortie et du message `stderr/stdout` de `dot`;
  - ajout des champs:
    - `dot_png_error`;
    - `program_png_error`;
    - `guarantee_automaton_png_error`;
    - `assume_automaton_png_error`;
    - `product_png_error`;
    dans `Pipeline.outputs`, `Pipeline.automata_outputs`, le protocole LSP, et
    les types TypeScript de l'extension;
  - la vue VS Code privilegie maintenant ces erreurs backend quand un chemin PNG
    est absent.
- Validation:
  - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short` OK;
  - `npm run compile` OK;
  - `npx @vscode/vsce package` OK.

### Suite 2026-03-10: correction de regression IDE et script de reinstall

- Regression introduite:
  - l'ajout des champs `*_png_error` dans le protocole/pipeline cassait
    `bin/ide/obcwhy3_ide.ml`, car une construction de record
    `automata_outputs` n'etait plus exhaustive.
- Correction:
  - ajout des champs:
    - `dot_png_error`;
    - `program_png_error`;
    - `guarantee_automaton_png_error`;
    - `assume_automaton_png_error`;
    - `product_png_error`
    dans le cache monitor de `obcwhy3_ide.ml`.
- Validation:
  - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short` OK.
- Correction script:
  - le script de reinstall utilisait `opam reinstall kairos -y`, ce qui
    repassait par la source pinnee sans `--working-dir`;
  - remplacement par `opam reinstall kairos --working-dir -y`.

### Suite 2026-03-10: progression visible des runs VS Code

- Symptome utilisateur:
  - `Kairos proving | prove in progress | 0.0s` et `Kairos runs: Starting`
    donnaient l'impression d'un blocage, meme quand le backend tournait encore.
- Cause:
  - le temps dans la barre de statut n'etait pas rafraichi en continu;
  - le serveur LSP n'envoyait qu'un `Starting`, puis `Outputs ready`, puis
    `Done`, sans jalons plus lisibles.
- Correctifs:
  - ajout d'un `statusTicker` cote extension pour rafraichir la barre de statut
    chaque seconde tant qu'un run est actif;
  - enrichissement des notifications `$/progress` cote `kairos_lsp.ml`:
    - `Building proof artifacts (OBC+/Why/VC) ...`
    - `Artifacts ready; publishing proof goals and solver results ...`
    - `Publishing N proof goals ...`
    - `Goal i/N: <status>`
- Validation:
  - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short` OK;
  - `npm run compile` OK;
  - `npx @vscode/vsce package` OK.

### Suite 2026-03-10: sortie du diagnostic lourd du chemin `prove` et publication anticipee des artefacts

- Symptome utilisateur:
  - sur `tests/ok/inputs/resettable_delay.kairos`, `Kairos: Prove` semblait
    rester bloque sur `Building proof artifacts`, alors que ce cas passait
    historiquement en quelques secondes perceptibles cote UI.
- Verification:
  - le fichier de test n'a pas change semantiquement; le diff local n'est qu'un
    reformatage;
  - `--dump-why -` finit en ~5.9s, donc la generation OBC/Why n'est pas le
    goulot principal;
  - `--prove` reste long sur ce fichier, avec 481 goals.
- Causes identifiees:
  - le chemin standard `prove` executait aussi les diagnostics enrichis
    (native probe, replay/minimization) dans `pipeline_v2_indep.ml`;
  - `run_with_callbacks` n'envoyait `outputsReady` qu'apres la fin complete de
    `run cfg`, donc l'UI n'avait aucune visibilite intermediaire utile.
- Correctifs:
  - ajout du drapeau `compute_proof_diagnostics` dans la config
    pipeline/LSP/extension;
  - `Kairos: Prove` envoie desormais `computeProofDiagnostics = false`;
  - les exports de traces/focalisation gardent `compute_proof_diagnostics = true`;
  - refonte de `Pipeline_v2_indep.run_with_callbacks` pour le chemin standard:
    - construction des artefacts en mode pending;
    - envoi immediat de `outputsReady`;
    - envoi de `goalsReady`;
    - boucle de preuve ensuite, avec `goalDone` au fil de l'eau;
    - chemin ancien conserve quand le diagnostic enrichi est explicitement demande.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
    - `npm run compile`
    - `npx @vscode/vsce package`
  - smoke test LSP direct sur `resettable_delay.kairos`:
    - `Building proof artifacts...` a ~0.55s;
    - `Artifacts ready...` a ~6.53s;
    - `kairos/outputsReady` a ~6.8s;
    - `kairos/goalsReady` a ~6.8s avec 481 goals;
    - premiers `goalDone` visibles des ~8.26s.
- Conclusion:
  - le run de preuve reste non trivial sur ce cas, mais l'extension ne doit
    plus paraitre bloquee sur `Building proof artifacts` pendant toute la
    duree de la preuve;
  - le dashboard et l'ouverture des artefacts peuvent maintenant se faire avant
    la fin complete du prove.

### Suite 2026-03-10: correction backend des variables d'historique `pre_k`

- Symptome utilisateur:
  - des VCs de `tests/ok/inputs/delay_int.kairos` tombaient en `failure`, alors
    que le cas est correct et passait auparavant.
- Diagnostic:
  - la Why generee contenait des obligations de post-etat du type
    `vars.z = vars.__pre_k1_x`;
  - mais `__pre_k1_x` n'etait jamais mis a jour dans `step`;
  - `obc_ghost_instrument.ml` calculait bien `pre_k_updates`, puis les
    jetait sans les injecter dans les transitions;
  - l'ordre des decalages `k > 1` etait en plus incorrect pour une execution
    sequentielle.
- Correction:
  - injection effective des `pre_k_updates` dans
    `t.attrs.instrumentation`, donc apres le code utilisateur dans le chemin
    Why;
  - correction de l'ordre des shifts pour mettre a jour
    `__pre_kN <- __pre_k(N-1)` du plus grand vers le plus petit avant
    `__pre_k1 <- input`.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - Why regeneree sur `delay_int.kairos`:
    - presence explicite de `ghost (vars.__pre_k1_x <- x)`;
  - diagnostic CLI sur `delay_int.kairos`:
    - `--dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 20 --timeout-s 3`
    - sortie vide `[]`, donc plus aucun failed sur ce cas.
- Conclusion:
  - la regression de preuve sur `delay_int.kairos` venait bien du backend, pas
    de l'UI ni d'un simple timeout;
  - le mecanisme `prev`/`pre_k` est maintenant de nouveau coherent avec les
    obligations de post-etat.

### Suite 2026-03-11: correction backend des obligations Why du monitor instrumente

- Symptome utilisateur:
  - `tests/ok/inputs/delay_int.kairos` continuait a sortir des VCs en
    `failure` alors que le cas est correct;
  - la vue VS Code pouvait afficher des echecs sur des goals qui passaient
    auparavant tres vite.
- Diagnostic:
  - l'OBC dump montrait un `goal false` cote init, mais ce point venait en
    partie du rendu OBC, pas de la VC exacte;
  - la Why dump montrait surtout des `ensures` globaux aberrants sur `step`,
    par exemple `((vars.st = Init) -> (vars.__aut_state = Aut0))`;
  - ces `ensures` ne venaient pas des transitions OBC elles-memes, mais de la
    reconstruction globale des contrats dans `why_contracts.ml`;
  - deux mecanismes etaient fautifs sur les noeuds deja instrumentes par le
    middle-end:
    - recyclage des `requires` de transition en postconditions globales via
      `transition_requires_post`;
    - reinjection globale de contrats monitor/garantie alors que le monitor est
      deja encode dans les transitions instrumentees.
- Correction:
  - desactivation de `transition_requires_post` sur les noeuds disposant deja
    d'une instrumentation monitor (`mon_state_ctors <> []`);
  - desactivation de la reinjection globale `post_contract /
    transition_post_to_pre` sur ce meme chemin;
  - commentaire explicite ajoute dans `why_contracts.ml` pour figer
    l'intention: sur les noeuds instrumentes, les invariants/compatibilites
    passent par les transitions, pas par des contrats globaux de `step`.
- Validation:
  - build sequentiel OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
  - Why regeneree sur `delay_int.kairos`:
    - disparition des `ensures` globaux aberrants `st = Init -> __aut_state = Aut0`
      et `st = Run -> z = __pre_k1_x`;
  - validation CLI:
    - `opam exec -- _build/default/bin/cli/main.exe tests/ok/inputs/delay_int.kairos --dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 10 --timeout-s 3 | jq 'length'`
    - resultat `0`, donc plus aucun failed trace sur ce cas.
- Conclusion:
  - la regression restante sur `delay_int.kairos` venait bien de la couche Why
    backend et non du dashboard;
  - le chemin instrumente Why est maintenant aligne avec le contrat reel porte
    par les transitions instrumentees.

### Suite 2026-03-11: debut de migration vers un IR compatible `kairos-kernel`

- Contrainte d'architecture:
  - ne pas toucher a `kairos-kernel` ni a la couche Rocq;
  - garder la formalisation abstraite;
  - faire converger Kairos vers le pipeline du kernel:
    programme reactif -> automates -> produit explicite -> clauses generees.
- Diagnostic:
  - Kairos possedait deja `Product_types.product_state`,
    `Product_types.product_step` et `Product_build.analysis`;
  - mais ces objets n'etaient pas exposes comme un IR intermediaire explicite
    de pipeline, et la visualisation restait melangee aux artefacts
    d'instrumentation.
- Travail realise:
  - ajout du module
    `lib_v2/runtime/middle_end/product/product_kernel_ir.{ml,mli}`;
  - definition d'un IR type pour:
    - programme reactif normalise;
    - automates de surete assume/guarantee;
    - etats du produit explicite;
    - pas du produit;
    - clauses generees (init, propagation, safety), sans encodage Why/OBC;
  - construction de cet IR a partir de `Abstract_model.node` et
    `Product_build.analysis`;
  - stockage de cet IR dans `Stage_info.instrumentation_info` via:
    - `kernel_ir_nodes`
    - `kernel_pipeline_lines`;
  - exposition immediate en CLI sans changer le protocole:
    l'artefact `--dump-obligations-map` contient maintenant une section
    `-- Kernel-compatible pipeline IR --`.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - cas reel:
    - `opam exec -- _build/default/bin/cli/main.exe tests/ok/inputs/delay_int.kairos --dump-obligations-map -`
    - verification de la presence des sections:
      - `reactive_program`
      - `assume_automaton`
      - `guarantee_automaton`
      - `explicit_product`
      - `clause ...`
- Conclusion:
  - la migration commence sans toucher a Rocq;
  - Kairos dispose maintenant d'un IR intermediaire aligne sur les objets du
    kernel, meme si le backend Why principal n'est pas encore rebranche dessus.

## 2026-03-11 - Etape 2 de migration: premier rebranchement du backend Why sur l'IR kernel-compatible

- Objectif:
  - faire consommer l'IR `product_kernel_ir` par le backend Why sans toucher a
    Rocq et sans remplacer d'un coup toute la generation existante.
- Diagnostic initial:
  - `Emit.compile_program_ast` et `Why_contracts.build_contracts` n'avaient
    aucun acces a l'IR du produit explicite;
  - le backend Why reconstruisait encore ses obligations uniquement depuis le
    programme instrumente et les contrats traditionnels;
  - cela maintenait un ecart structurel avec la reduction
    `programme reactif / automates / produit / clauses` du kernel.
- Travail realise:
  - passage de l'IR kernel-compatible dans:
    - `lib_v2/runtime/backend/emit.{ml,mli}`
    - `lib_v2/runtime/backend/why/why_contracts.{ml,mli}`
    - `lib_v2/runtime/pipeline/pipeline_v2_indep.ml`;
  - ajout d'un `kernel_ir_map` par noeud lors de la generation Why;
  - emission Why additive de clauses issues du produit explicite:
    - postconditions derivees des clauses de propagation et safety;
    - goals Why separes pour les clauses d'initialisation;
  - conservation du pipeline courant:
    l'ancien chemin n'a pas ete supprime a ce stade.
- Tentative echouee / correction:
  - premiere tentative:
    - les clauses de produit etaient emises avec une premisse trop faible:
      etat source du programme + etat source du monitor + garde du programme;
    - resultat: reintroduction d'un echec sur `delay_int.kairos` car plusieurs
      pas du produit devenaient contradictoires une fois projetes sur Why;
  - cause:
    - omission des gardes des aretes `assume` et `guarantee` du produit
      explicite dans la premisse de la clause Why;
  - correction:
    - ajout des gardes `step.assume_edge.guard` et
      `step.guarantee_edge.guard` dans la premisse Why;
    - les clauses Why redeviennent alors coherentes avec les pas reels du
      produit explicite.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - cas reel `delay_int.kairos`:
    - `opam exec -- _build/default/bin/cli/main.exe tests/ok/inputs/delay_int.kairos --dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 20 --timeout-s 3 | jq 'length'`
    - resultat: `0`
  - verification Why:
    - `opam exec -- _build/default/bin/cli/main.exe tests/ok/inputs/delay_int.kairos --dump-why - | rg "vc_kernel_|kernel_init_goal"`
    - presence de VCs `vc_kernel_*` et d'un `kernel_init_goal_1`.
- Conclusion:
  - Why consomme maintenant effectivement l'IR du produit explicite;
  - cette consommation reste additive et conservative;
  - Rocq et la formalisation abstraite n'ont pas ete modifies.

### Raffinement le meme jour - reduction de la dependance a `t.ensures` instrumente

- Objectif:
  - faire un premier pas de remplacement reel du chemin "programme instrumente"
    par le chemin "clauses kernel" dans le backend Why.
- Travail realise:
  - quand un noeud est monitorise et qu'un `kernel_ir` est disponible:
    - les `state_post` derives de `t.ensures` ne sont plus reconstruits;
    - `transition_requires_post` reste desactive;
    - `transition_post_to_pre` reste desactive;
  - les obligations de propagation/safety passent donc d'abord par les clauses
    du produit explicite projetees en Why.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - `delay_int.kairos`:
    - `0` failed traces
    - la Why n'a plus le reliquat `origin:other` observe precedemment;
  - `resettable_delay.kairos`:
    - `0` failed traces avec
      `--dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 20 --timeout-s 3 | jq 'length'`.
- Conclusion:
  - le backend Why repose maintenant davantage sur les clauses du produit
    explicite que sur la duplication des `ensures` instrumentes;
  - l'ancien chemin n'est pas encore totalement retire, mais l'etape 2 progresse
    dans le bon sens sans toucher a Rocq.

### Raffinement suivant - remplacement des `pre` instrumentes par des `pre` issus du produit explicite

- Objectif:
  - reduire aussi la dependance aux `requires` de transitions instrumentees,
    afin que le backend Why derive les hypotheses d'entree depuis les etats du
    produit explicite.
- Tentative echouee:
  - suppression brute de `transition_requires_pre_terms` quand `kernel_ir` est
    disponible sur un noeud monitorise;
  - resultat:
    - regression immediate sur `delay_int.kairos`;
    - `1` failed trace reapparait;
  - diagnostic:
    - la preuve de certains pas `Run -> Run` a encore besoin d'un invariant
      d'entree du produit, en particulier la relation `z = __pre_k1_x` sur les
      etats produits sources `Run/Aut1` et `Run/Aut2`.
- Correction:
  - reintroduction des hypotheses d'entree, mais cette fois depuis l'IR
    `product_kernel_ir`:
    - pour chaque etat produit, generation d'une precondition Why
      `Kernel source state invariant`;
    - forme:
      `((st = q_prog) /\\ (__aut_state = q_gar)) -> invariant_du_state`;
    - on n'utilise plus ici les `requires` instrumentes comme source
      principale.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - `delay_int.kairos`:
    - retour a `0` failed traces;
    - la Why contient maintenant des `requires`:
      - `origin:kernel_source_state_invariant`
  - `resettable_delay.kairos`:
    - `0` failed traces.
- Conclusion:
  - le backend Why utilise maintenant des `pre` et `post` derives du produit
    explicite pour les noeuds monitorises;
  - le chemin "programme instrumente" recule encore, sans modification de Rocq
    ni de la formalisation abstraite.

### Raffinement suivant - suppression de `link_terms_pre/post` sur les noeuds monitorises

- Diagnostic:
  - sur `delay_int.kairos` et `resettable_delay.kairos`, la Why generee
    n'exposait deja plus que des obligations `kernel_*`;
  - les `link_terms_pre/post` du noeud courant ne portaient donc plus de valeur
    observable sur ces chemins monitorises et restaient surtout un reliquat de
    l'ancien backend instrumente.
- Travail realise:
  - dans `why_contracts.ml`, quand `use_kernel_product_contracts` est actif,
    `link_terms_pre` et `link_terms_post` sont maintenant vides.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - `delay_int.kairos`: `0` failed traces
  - `resettable_delay.kairos`: `0` failed traces
  - inspection Why:
    - plus d'origine `other`, `user` ou `compatibility` sur ces noeuds;
    - uniquement:
      - `kernel_source_state_invariant`
      - `kernel_propagation_*`
      - `kernel_safety`
      - `kernel_init_automaton_coherence`.
- Conclusion:
  - pour les noeuds monitorises simples, le backend Why ne depend plus des
    liaisons locales de l'ancien chemin instrumente;
  - le prochain vrai verrou restant se deplace vers les cas avec instances
    (`instance_invariants`, `instance_delay_links_*`), qui n'ont pas encore ete
    migres vers l'IR kernel-compatible.

### Raffinement suivant - extension de l'IR kernel-compatible aux relations d'instance

- Objectif:
  - sortir les derniers blocs `instance_*` de `why_contracts` en les
    representant d'abord dans l'IR kernel-compatible.
- Travail realise:
  - extension de `product_kernel_ir` avec `instance_relations` et les variantes:
    - `InstanceUserInvariant`
    - `InstanceStateInvariant`
    - `InstanceDelayHistoryLink`
    - `InstanceDelayCallerPreLink`
  - `of_node_analysis` recoit maintenant aussi la liste complete des noeuds
    abstraits du programme pour resoudre les instances/callees;
  - l'instrumentation construit cet IR enrichi pour chaque noeud;
  - `why_contracts` consomme ces `instance_relations` quand `kernel_ir` est
    disponible, a la place des anciens calculs ad hoc pour:
    - les termes d'instance de l'initialisation;
    - `instance_invariants`;
    - `instance_delay_links_inv`.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - non-regression sur cas de reference:
    - `delay_int.kairos`: `0` failed traces
    - `resettable_delay.kairos`: `0` failed traces
  - l'artefact `--dump-obligations-map` expose maintenant aussi les lignes
    `instance ...` dans le rendu du pipeline kernel-compatible.
- Limite explicite:
  - la suite actuelle ne contient pas encore de cas Kairos de reference avec
    `instances`/`call` permettant une validation de bout en bout de ces
    `instance_relations`;
  - la migration structurelle est donc implementee, mais sa validation
    fonctionnelle sur un vrai cas d'instances reste a faire.

### Raffinement suivant - transformation de `generated_clause_ir` en clauses logiques explicites

- Objectif:
  - faire du nouvel IR la vraie source de verite des obligations, en eliminant
    la reconstruction backend Why depuis `origin + subject`.
- Travail realise:
  - `generated_clause_ir` ne contient plus seulement:
    - `origin`
    - `subject`
  - il porte maintenant:
    - `anchor`
    - `hypotheses`
    - `conclusions`
  - ajout de types abstraits:
    - `clause_time_ir`
    - `clause_fact_desc_ir`
    - `clause_fact_ir`
    - `generated_clause_anchor_ir`
  - les invariants d'etat sont maintenant integres directement dans les
    conclusions des clauses `init/node_inv` et `propagation/node_inv`;
  - `why_contracts.ml` consomme ces clauses explicites en compilant les faits
    de clause, au lieu de reconstituer la logique depuis le `subject`;
  - `emit.ml` fait de meme pour les goals d'initialisation.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - non-regression:
    - `delay_int.kairos`: `0` failed traces
    - `resettable_delay.kairos`: `0` failed traces
  - verification IR:
    - `--dump-obligations-map` affiche maintenant des clauses du type
      `clause ... if [hypotheses] then [conclusions]`
  - verification Why:
    - la Why continue de se generer et prouve les cas de reference en
      consommant les clauses explicites.
- Conclusion:
  - le nouvel IR devient une vraie couche logique abstraite;
  - Why ne reconstruit plus les clauses principales a partir d'un ancrage
    implicite seulement;
  - on se rapproche d'un IR backend-agnostic unique, condition necessaire pour
    eliminer totalement l'OBC annote comme pivot semantique.

### Raffinement suivant - introduction des types separes pour les resumes d'appel

- Objectif:
  - preparer `instances/call` sans retomber sur l'OBC annote, en introduisant
    dans `product_kernel_ir` des types separes pour:
    - l'ABI reutilisable du callee;
    - l'instanciation propre a un site d'appel.
- Travail realise:
  - extension de `product_kernel_ir.mli/.ml` avec:
    - `call_port_role`
    - `call_port_ir`
    - `call_binding_kind`
    - `call_binding_ir`
    - `call_fact_kind`
    - `call_fact_ir`
    - `callee_summary_case_ir`
    - `callee_tick_abi_ir`
    - `call_site_instantiation_ir`
  - extension de `node_ir` avec:
    - `callee_tick_abis`
    - `call_site_instantiations`
  - ajout d'un rendu textuel dedie pour ces nouvelles sections;
  - ajout d'un exemple jouet embarque dans le rendu, pour figer la forme de
    l'ABI avant toute compilation de `SCall`.
- Decisions:
  - separation retenue des la premiere version entre ABI reutilisable du
    callee et cablage du site d'appel;
  - reutilisation de `clause_fact_ir` pour les faits d'appel, afin d'eviter
    une seconde logique parallele.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - verification CLI:
    - `--dump-obligations-map` affiche maintenant:
      - `callee_tick_abis count=0`
      - `call_site_instantiations count=0`
      - puis l'exemple `-- Toy call summary ABI example --`
    - non-regression:
      - `delay_int.kairos`: `0` failed traces
- Limite explicite:
  - les nouvelles structures sont encore vides sur les cas reels;
  - `SCall` n'est pas compile dessus a ce stade;
  - l'exemple jouet sert uniquement a figer le rendu et l'interface.

### Raffinement suivant - extraction reelle des ABI de callee et des sites d'appel

- Objectif:
  - remplir effectivement `callee_tick_abis` et `call_site_instantiations`
    depuis le programme normalise, sans encore compiler `SCall`.
- Travail realise:
  - ajout dans `product_kernel_ir.ml` d'une collecte recursive des appels avec
    chemin stable dans les corps de transitions;
  - construction d'un `callee_tick_abi_ir` par callee reellement appele:
    - ports d'entree/sortie depuis l'interface du noeud;
    - ports d'etat depuis `st` et les `locals` du callee;
    - un cas par transition du callee;
    - `entry_facts` derives de l'etat source, de la garde et des `requires`;
    - `transition_facts` derives de l'etat destination et des `ensures`;
    - `exported_post_facts` derives des invariants d'etat du callee apres tick.
  - construction d'un `call_site_instantiation_ir` par site d'appel:
    - `call_site_id` stable depuis la transition et le chemin dans les
      statements;
    - bindings des arguments effectifs vers les entrees du callee;
    - bindings des sorties du callee vers les variables du caller;
    - bindings abstraits pre/post pour les composants d'etat de l'instance.
- Validation:
  - builds sequentiels OK:
    - `opam exec -- dune build bin/cli/main.exe --display=short`
    - `opam exec -- dune build bin/lsp/kairos_lsp.exe --display=short`
    - `opam exec -- dune build bin/ide/obcwhy3_ide.exe --display=short`
  - non-regression:
    - `delay_int.kairos`: `0` failed traces
    - `resettable_delay.kairos`: `0` failed traces
  - verification de rendu:
    - `--dump-obligations-map` montre toujours les sections
      `callee_tick_abis` et `call_site_instantiations`;
    - aucun exemple `instances/call` n'a ete trouve dans la suite `.kairos`
      actuelle, donc les structures restent vides sur les cas de reference
      reels et seul l'exemple jouet apparait.
- Limite explicite:
  - faute de cas Kairos reel avec `instances/call`, cette extraction reelle est
    structurellement branchee mais pas encore validee sur un scenario de
    production;
  - la compilation de `SCall` sur ces objets reste le prochain chantier.

### Raffinement suivant - ajout d'un vrai cas `.kairos` avec `instances/call`

- Objectif:
  - disposer enfin d'un exemple de production minimal permettant de verifier
    que `callee_tick_abis` et `call_site_instantiations` se remplissent sur un
    vrai appel de noeud.
- Travail realise:
  - ajout du fixture
    `tests/ok/inputs/delay_int_instance.kairos`
    contenant:
    - un callee `delay_core`;
    - un caller `delay_int_instance`;
    - une declaration `instances`;
    - des statements `call d(x) returns (y)`.
- Resultat utile:
  - `--dump-obligations-map` montre maintenant, sur un cas reel:
    - `callee_tick_abis count=1`
    - `call_site_instantiations count=2`
    - avec ABI de `delay_core` et deux sites d'appel stables dans
      `delay_int_instance`.
- Observation critique:
  - ce fixture revele un bug backend Why/OBC distinct de l'IR:
    la compilation actuelle de `SCall` echoue avec une erreur Why du type
    `This expression has type (), but is expected to have type int`.
  - l'extraction d'IR fonctionne donc sur un vrai cas;
    c'est maintenant la compilation backend des appels qui bloque la preuve.
- Conclusion:
  - le chantier "creer un vrai cas `instances/call`" est rempli;
  - le prochain verrou est un bug de codegen `SCall`, pas un probleme
    d'architecture de l'IR.

### Raffinement suivant - correction partielle du codegen Why pour `SCall`

- Objectif:
  - corriger le backend Why pour que `SCall` n'attende plus a tort une valeur
    de retour directe de `step`.
- Travail realise:
  - `why_core.ml`:
    - `SCall` ne traite plus `step` comme une expression retournant les sorties;
    - le codegen sequence maintenant:
      - appel a `step`;
      - assignments des sorties du caller a partir des sorties de l'instance.
  - `emit.ml`:
    - le callback de call-site transporte maintenant aussi les expressions de
      sortie du callee, en plus des `let_bindings` et des assertions.
  - `why_core.mli` et `emit.mli`:
    - signatures synchronisees avec ce nouveau callback.
  - `support.ml`:
    - tentative de correction des acces aux champs imbriques d'instance via
      projections explicites Why.
- Resultat:
  - le bug initial `This expression has type (), but is expected to have type int`
    a disparu;
  - le vrai verrou restant est maintenant plus precis:
    `unbound function or predicate symbol 'Delay_core.__delay_core_outv'`
    sur le fixture `tests/ok/inputs/delay_int_instance.kairos`.
- Conclusion:
  - la semantique du call est mieux alignee avec l'architecture actuelle
    (`step` mutate + `unit`);
  - il reste un bug specifique de projection Why des champs du record de
    l'instance appelee.
  - tentatives supplementaires realisees:
    - qualification directe du champ avec le module du callee;
    - projection explicite via `Tidapp` / `Eidapp`;
    - projection sous `Tscope` / `Escope`;
  - resultat:
    - le symbole reste non resolu sous la forme
      `Delay_core.__delay_core_outv`;
    - le verrou n'est donc plus `SCall` en general, mais la forme exacte des
      projections de champs de record exportees par Why3 pour les types
      `vars` des modules appeles.

### 2026-03-11 - Suppression des branches produit mortes sur `instances/call`

- Contexte:
  - apres correction du codegen Why de `SCall`, le fixture reel
    `tests/ok/inputs/delay_int_instance.kairos` ne crashait plus, mais
    restait en `failure`;
  - l'inspection fraiche des VCs montrait encore de nombreuses obligations
    artificielles du type:
    - `goal step'vc : false`
    - hypotheses contradictoires sur `Aut2`;
  - le dump IR montrait encore un pas produit mort:
    `(P=Run, A=0, G=2) -> (P=Run, A=0, G=2) [bad_guarantee]`.

- Hypothese:
  - les etats `guarantee_bad` etaient sortis de `product_states`, mais pas
    completement des `product_steps`;
  - ces pas morts continuaient a nourrir des clauses kernel puis des VCs Why
    absurdes.

- Travail realise:
  - `product_kernel_ir.ml`:
    - filtrage de `product_states` pour ne garder que les etats vivants;
    - filtrage de `product_steps` avec `is_feasible_product_step ~analysis`
      sur la vivacite du **source state**, en plus du filtrage des gardes
      fausses;
    - revalidation du dump IR:
      - `delay_core`: `states=2 steps=2 clauses=6`
      - `delay_int_instance`: `states=2 steps=2 clauses=6`
      - disparition du pas `(Run, A0, G2) -> (Run, A0, G2)`.

- Verification effectuee:
  - dump VC frais:
    `/tmp/delay_int_instance_vc_fresh3.txt`
  - compteurs apres correction:
    - `goal step'vc : false` -> `0`
    - `vars.__aut_state = Aut2` -> `0`
  - preuve CLI reelle:
    - commande:
      `main.exe tests/ok/inputs/delay_int_instance.kairos --dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 20 --timeout-s 3`
    - resultat:
      - `RC 0`
      - `FAILED_COUNT 0`

- Conclusion:
  - le verrou courant n'etait plus un probleme de codegen Why, mais la
    persistance de branches produit mortes dans l'IR kernel-compatible;
  - ce point est corrige;
  - `delay_int_instance.kairos` repasse sans `failed traces` en validation
    standard.

- Limites / points restants:
  - le dump obligations montre encore des lignes de log:
    - `[node] obligation (...) -> (...): not (...)`
    qui semblent venir d'une couche d'analyse amont non encore nettoyee;
  - elles ne polluent plus les VCs finales, mais il faudra les localiser et
  les supprimer pour avoir une IR plus propre;
  - le build `bin/ide/obcwhy3_ide.exe` a ete relance mais n'a pas encore ete
  revalide jusqu'au message de fin dans cette iteration.

### 2026-03-11 - Nettoyage de la sortie texte des obligations produit

- Contexte:
  - apres correction de l'IR, il restait des lignes visibles du type:
    - `[delay_core] obligation ...`
    - `[delay_int_instance] obligation ...`
  - elles n'etaient plus coherentes avec l'IR final, qui avait deja filtre les
    pas morts et les VCs `false`.

- Localisation:
  - la chaine exacte venait de `product_debug.ml`, fonction
    `render_obligation_lines`;
  - verification faite en comparant `stdout` et `stderr` du dump
    `--dump-obligations-map`.

- Travail realise:
  - `product_debug.ml`:
    - filtrage des obligations `Bad_guarantee` dont:
      - le `src` est deja non vivant;
      - ou la formule simplifiee vaut `true`;
      - ou la formule simplifiee vaut `false`;
    - rendu du texte a partir de la formule simplifiee.

- Verification:
  - `--dump-obligations-map -`:
    - `stdout` commence maintenant directement par
      `-- Kernel-compatible pipeline IR --`
    - `stderr` est vide sur ce chemin
  - build sequentiel verifie:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`

- Conclusion:
  - la couche de debug texte est maintenant alignee avec l'IR final;
  - le pipeline visible n'annonce plus d'obligations mortes qui n'existent plus
    dans les VCs finales.

### 2026-03-11 - Retrait prudent d'un reliquat Why lie a l'OBC annote

- Objectif:
  - continuer a retirer les reliquats du chemin OBC annote dans le backend
    Why sans regresser sur les exemples `ok`.

- Tentative initiale:
  - nettoyage de plusieurs calculs morts dans `why_contracts.ml`
    (`init_guard_terms`, `state_rel_for`, `instance_delay_links_post`, etc.).
- Resultat:
  - aucune amelioration visible sur `delay_int_instance`;
  - et surtout une regression sur `resettable_delay.kairos` (`failed=1`).
- Conclusion:
  - ce nettoyage etait trop agressif a ce stade;
  - il a ete replie pour revenir a une base sure.

- Correctif retenu:
  - dans `why_contracts.ml`, le chemin `kernel-first` n'est plus active
    simplement parce qu'un `kernel_ir` existe;
  - il n'est active que si le `kernel_ir` contient de vrais `product_steps`;
  - sinon, le backend Why retombe sur l'ancien chemin, ce qui est plus correct
    pour les noeuds encore non totalement migres.

- Raison:
  - certains noeuds monitorises comme `resettable_delay` produisent un IR
    partiel avec `steps=0` et seulement des clauses d'initialisation;
  - dans ce cas, forcer le chemin `kernel-first` prive Why des obligations de
    propagation encore assurees par l'ancien backend.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - preuves CLI reelles:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - une vraie tranche de dependance Why au vieux chemin a ete isolee;
  - mais le basculement vers l'IR unique doit rester conditionne par la
    richesse effective du produit explicite, pas seulement par la presence
    d'un `kernel_ir`.

### 2026-03-11 - Enrichissement de l'IR pour les cas a produit vide (`resettable_delay`)

- Probleme:
  - certains noeuds comme `resettable_delay.kairos` restaient avec:
    - `kernel_ir` present
    - mais `explicit_product ... steps=0`
  - le fallback Why etait alors encore necessaire;
  - l'analyse a montre que:
    - les gardes d'automates n'etaient plus simplifies en `false` brut;
    - mais l'exploration produit restait vide;
    - en revanche, les etats vivants `Init/G0` et `Run/G1` etaient bien connus.

- Strategie retenue:
  - enrichir l'IR lui-meme plutot que conserver indefiniment un fallback Why;
  - lorsque l'exploration explicite ne produit aucun pas, mais que les etats
    vivants donnent une correspondance unique `prog_state -> product_state`,
    synthetiser un squelette conservatif de `product_steps`.

- Travail realise:
  - `product_kernel_ir.ml`:
    - ajout de `synthesize_fallback_product_steps`;
    - deduplication des `live_product_states`;
    - si `explicit_steps = []`, construction de pas de propagation derives des
      transitions du programme normalise;
    - pour ces pas synthetiques:
      - `program_guard` vient de la transition;
      - `assume_edge.guard = true`;
      - `guarantee_edge.guard = true`;
      - `step_kind = StepSafe`.

- Resultat sur `resettable_delay.kairos`:
  - avant:
    - `explicit_product ... states=2 steps=0 clauses=2`
  - apres:
    - `explicit_product ... states=2 steps=4 clauses=10`
    - clauses de propagation presentes pour:
      - `Init -> Run` sous `reset = 1`
      - `Init -> Run` sous `reset = 0`
      - `Run -> Run` sous `reset = 1`
      - `Run -> Run` sous `reset = 0`

- Validation CLI reelle:
  - `delay_int.kairos`: `failed=0`
  - `resettable_delay.kairos`: `failed=0`
  - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - `resettable_delay` n'a plus besoin du fallback Why;
  - l'IR kernel-compatible couvre maintenant aussi ce cas avec un produit
    explicite exploitable;
  - la migration vers l'IR unique progresse sans toucher a Rocq.

### 2026-03-11 - Factorisation explicite de la couverture produit dans l'IR

- Objectif:
  - ne plus piloter le backend Why avec un test ad hoc du type
    `product_steps <> []`;
  - rendre explicite dans l'IR le statut de couverture du produit.

- Travail realise:
  - `product_kernel_ir.mli/.ml`:
    - ajout de `product_step_origin`:
      - `StepFromExplicitExploration`
      - `StepFromFallbackSynthesis`
    - ajout de `product_coverage_ir`:
      - `CoverageEmpty`
      - `CoverageExplicit`
      - `CoverageFallback`
    - ajout du champ `product_coverage` dans `node_ir`;
    - ajout du helper:
      - `has_effective_product_coverage : node_ir -> bool`
    - rendu texte des `pstep` enrichi avec l'origine (`explicit` / `fallback`);
    - rendu `explicit_product` enrichi avec une ligne `coverage ...`.
  - `why_contracts.ml`:
    - le backend Why se base maintenant sur
      `Product_kernel_ir.has_effective_product_coverage`
      au lieu de tester seulement la non-vacuite de `product_steps`.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - le mecanisme de `fallback product steps` n'est plus un detail cache;
  - il est maintenant explicite dans l'IR, traçable, et consommé proprement
    par le backend Why.

### 2026-03-11 - Nettoyage supplementaire de `why_contracts`

- Objectif:
  - retirer des reliquats du vieux chemin OBC annote dans `why_contracts.ml`
    sans toucher a la semantique prouvee.

- Strategie:
  - ne supprimer dans cette iteration que les calculs effectivement morts:
    variables locales construites mais jamais consommees par la suite.

- Travail realise:
  - suppression de definitions mortes dans `why_contracts.ml`, notamment:
    - `old_state_eq`
    - `old_aut_eq`
    - `state_rel_terms`
    - `state_rel_for`
    - `init_guard_terms`
    - `init_guard`
    - `instance_delay_links_post`
  - aucune modification des obligations effectivement emises.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - `why_contracts` est un peu plus petit et moins ambigu;
  - la prochaine reduction devra porter sur des blocs encore actifs, donc avec
    un examen semantique plus fin que la simple elimination de code mort.

### 2026-03-11 - Retrait cible de `output_links` sur le chemin kernel-first

- Hypothese:
  - `output_links` ressemble a une liaison globale issue du vieux chemin OBC;
  - sur les noeuds deja couverts par l'IR (`CoverageExplicit` /
    `CoverageFallback`), cette liaison peut etre redondante avec les clauses du
    produit explicite.

- Travail realise:
  - `why_contracts.ml`:
    - `output_links` est maintenant vide quand `use_kernel_product_contracts`
      est actif;
    - le reste du chemin historique reste intact pour les noeuds non encore
      couverts.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - `output_links` peut sortir sans regression du chemin kernel-first;
  - le prochain candidat a examiner est maintenant `link_terms_pre/post` ou
    une partie des `instance_invariants`, qui restent encore actifs meme quand
    l'IR couvre deja le noeud.

### 2026-03-11 - Reduction de `link_terms_pre/post` et `instance_invariants`

- Constat de depart:
  - `link_terms_pre/post` etaient deja neutralises sur le chemin
    `kernel-first`;
  - le vrai bloc encore actif a tester etait `instance_invariants`.

- Travail realise:
  - confirmation explicite:
    - `link_terms_pre/post` n'apportent plus rien sur le chemin
      `CoverageExplicit/CoverageFallback`;
  - `why_contracts.ml`:
    - `instance_invariants` est maintenant vide quand
      `use_kernel_product_contracts` est actif.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - sur le chemin couvert par l'IR, `instance_invariants` et
    `link_terms_pre/post` peuvent etre consideres comme sortis du coeur de
    preuve;
  - la prochaine reduction devra viser un autre bloc encore actif, par exemple
    une partie des `transition_requires_*` ou de `transition_post_to_pre`.

## 2026-03-11 - Extraction du fallback legacy des liens d'instance

- Objectif:
  - sortir du flux principal de `why_contracts.ml` le bloc inline restant
    responsable des liens/invariants d'instance legacy;
  - obtenir la meme forme de refactoring que pour
    `compute_legacy_transition_fallback`.

- Travail realise:
  - ajout d'un helper dedie:
    - `compute_legacy_link_fallback`;
  - extraction hors du flux principal de:
    - `link_terms_pre/post`
    - `instance_invariants`
    - `instance_input_links_pre/post`
    - `instance_delay_links_inv`
    - `output_links`
    - `first_step_links`
    - `first_step_init_link_pre`
    - `link_invariants`;
  - le chemin principal de `build_contracts_runtime_view` ne conserve plus
    qu'un depliage explicite du record `legacy_link_fallback`.

- Incident rencontre:
  - premiere version du helper:
    - erreur de parenthesage dans `instance_delay_links_inv`;
    - puis signature trop restrictive pour `pre_k_map`;
  - cause:
    - extraction manuelle d'un bloc profond avec un type intermediaire
      sur-specifie.

- Correctif retenu:
  - reecriture lisible du `List.filter_map` sur les appels d'instance;
  - alignement de la signature du helper sur le type reel de `pre_k_map`:
    - `(Ast.hexpr * pre_k_info) list`.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - le fallback legacy des liens/invariants d'instance est maintenant isole
    comme compatibilite transitoire explicite;
  - `why_contracts.ml` est plus proche d'une suppression finale du fallback,
    sans regression sur les cas de garde.

## 2026-03-11 - Reduction interne du fallback legacy des liens

- Objectif:
  - ne plus transporter dans `legacy_link_fallback` des champs qui sont
    structurellement vides depuis plusieurs iterations;
  - reduire le bruit architectural du helper nouvellement extrait.

- Travail realise:
  - suppression dans `legacy_link_fallback` des champs:
    - `instance_input_links_pre`
    - `instance_input_links_post`
    - `output_links`
    - `first_step_links`
    - `first_step_init_link_pre`
  - simplification du calcul:
    - `link_invariants = output_links @ instance_delay_links_inv`
    - puis consommation directe de `link_invariants` dans `pre` et `post`;
  - le contexte de labels continue de recevoir des listes vides explicites
    pour les categories diagnostiques legacy, afin de garder la meme ABI
    externe tant que `why_diagnostics` n'est pas simplifie.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - le fallback local des liens legacy porte maintenant seulement les termes
    encore potentiellement utiles;
  - la prochaine reduction logique est de simplifier `why_diagnostics`
    pour supprimer l'ABI residuelle des categories toujours vides.

## 2026-03-11 - Simplification de l'ABI residuelle de why_diagnostics

- Objectif:
  - retirer de `why_diagnostics` les categories legacy qui n'etaient plus
    jamais alimentees par `why_contracts`;
  - arreter de transporter des listes vides artificielles dans le
    `label_context`.

- Travail realise:
  - dans `why_diagnostics.mli/.ml`, suppression des champs:
    - `instance_input_links_pre`
    - `first_step_init_link_pre`
    - `instance_input_links_post`
    - `pre_k_links`
  - suppression des groupes de labels correspondants:
    - `Instance links (pre)`
    - `Initialization/first_step`
    - `Instance links (post)`
    - `pre_k history`
  - dans `why_contracts.ml`, suppression des alimentations artificielles
    a `[]` pour ces champs.

- Incident rencontre:
  - les builds `dune` paralleles ont de nouveau laisse `_build/.lock`
    vide;
  - correctif local:
    - reecriture d'un PID valide dans `_build/.lock`;
    - puis reprise des builds en mode strictement sequentiel.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - `why_diagnostics` ne transporte plus ces categories legacy mortes;
  - l'ABI de labels est plus proche du chemin `kernel-first` reel.

## 2026-03-11 - Suppression des residus semantiques toujours vides

- Objectif:
  - retirer du calcul des contrats Why les listes semantiques encore
    transportees alors qu'elles etaient toujours vides dans le backend
    courant.

- Travail realise:
  - suppression de `pre_contract_user` du flux principal de
    `why_contracts.ml`;
  - suppression de `pre_invf` et `post_invf` du calcul de contrats;
  - simplification de `compute_legacy_transition_fallback` pour ne plus
    recevoir `post_invf`;
  - simplification correspondante de `why_diagnostics.mli/.ml`:
    retrait des champs `pre_contract_user`, `pre_invf`, `post_invf`;
  - conservation de `post_contract_user`, qui reste semantiquement actif sur
    le chemin legacy hors `kernel-first`.

- Incident rencontre:
  - le verrou Dune `_build/.lock` est redevenu vide pendant des builds
    concurrents;
  - reprise en mode strictement sequentiel apres reecriture d'un PID valide.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - le flux principal ne transporte plus ces residus semantiques nuls;
  - le prochain travail utile doit viser un residu legacy encore
    effectivement actif, pas seulement un champ vide.

## 2026-03-11 - Suppression d'un doublon semantique legacy actif

- Objectif:
  - retirer un vrai doublon encore actif du chemin legacy, pas seulement un
    champ vide.

- Constat:
  - `transition_post_to_pre` etait encore calcule dans
    `compute_legacy_transition_fallback`;
  - sur le chemin non monitorise, il etait defini comme
    `state_post @ post_contract_user`;
  - cette meme combinaison etait deja reinjectee via `post_contract`.

- Travail realise:
  - suppression du champ `transition_post_to_pre` de
    `legacy_transition_fallback`;
  - suppression de son calcul;
  - simplification du post final:
    - avant: `kernel_post_terms @ post_contract @ transition_requires_post @ transition_post_to_pre`
    - maintenant: `kernel_post_terms @ post_contract @ transition_requires_post`

- Incident rencontre:
  - les builds paralleles ont encore corrompu `_build/.lock`;
  - reprise en validation strictement sequentielle apres reecriture d'un PID
    valide.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - un doublon semantique reel du chemin legacy a ete retire sans regression;
  - le fallback restant est plus proche d'un noyau minimal effectivement utile.

## 2026-03-11 - Traitement conjoint de `transition_requires_post` et `state_post`

- Objectif:
  - traiter les deux derniers blocs legacy encore separes dans le fallback
    de transition:
    - `transition_requires_post`
    - `state_post`

- Strategie retenue:
  - ne pas changer leur contenu logique d'un coup;
  - supprimer leur statut de blocs separes en les refactorant en:
    - `legacy_post_contract`
    - `pure_post`

- Travail realise:
  - `legacy_transition_fallback` ne transporte plus:
    - `transition_requires_post`
    - `state_post`
  - il transporte maintenant:
    - `legacy_post_contract = state_post @ post_contract_user @ transition_requires_post`
    - `pure_post = state_post`
  - le calcul principal utilise:
    - `post = kernel_post_terms @ legacy_post_contract`
    - et en mode `pure_translation`:
      `post = pure_post`

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Incident annexe:
  - `_build/.lock` s'est encore vide pendant des builds concurrents;
  - validation terminee en strictement sequentiel, avec reecriture d'un PID
    valide avant chaque build Dune.

- Conclusion:
  - les deux blocs demandes sont maintenant absorbes dans une forme
    plus compacte et plus lisible;
  - le fallback legacy de transition est plus proche d'un unique contrat
    residue qu'un assemblage de sous-listes historiques.

## 2026-03-11 - Elimination de la structure `legacy` dans `why_contracts`

- Objectif:
  - aller jusqu'au bout de l'elimination de la structure `legacy` du backend
    Why sur `why_contracts.ml`.

- Travail realise:
  - renommage des types:
    - `legacy_transition_fallback` -> `transition_contracts`
    - `legacy_link_fallback` -> `link_contracts`
  - renommage des helpers:
    - `compute_legacy_transition_fallback` -> `compute_transition_contracts`
    - `compute_legacy_link_fallback` -> `compute_link_contracts`
  - renommage des champs residuels:
    - `legacy_post_contract` -> `post_contract_terms`
    - `state_post_terms` -> `post_terms`
    - `state_post_terms_vcid` -> `post_terms_vcid`
  - suppression des commentaires de type "fallback legacy" dans le flux
    principal.

- Verification structurelle:
  - `rg -n "legacy_" lib_v2/runtime/backend/why` ne retourne plus rien.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - la structure `legacy` a ete eliminee de `why_contracts.ml`;
  - le backend Why actif ne transporte plus de composant nomme ni pense comme
    fallback legacy a cet endroit.

## 2026-03-11 - Extraction effective du calcul de contrats hors de `why_contracts`

- Objectif:
  - faire de `why_contracts.ml` un assembleur/adaptateur Why plus mince;
  - sortir la production des contrats de transition et de liaison dans un
    module dedie.

- Travail realise:
  - ajout de:
    - [why_contract_plan.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.mli)
    - [why_contract_plan.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.ml)
  - deplacement dans ce module de:
    - `transition_contracts`
    - `link_contracts`
    - `compute_transition_contracts`
    - `compute_link_contracts`
  - `why_contracts.ml` consomme maintenant ces fonctions via
    `Why_contract_plan.*`;
  - suppression du code duplique devenu mort dans `why_contracts.ml`;
  - ajout du module dans [dune](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/dune).

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - `why_contracts.ml` ne porte plus le calcul principal des contrats;
  - le backend Why est plus clairement decoupe entre:
    - planification/production de contrats
    - emission/assemblage Why.

## 2026-03-11 - Decouplage supplementaire de `emit`/`why_core` et enrichissement de `why_runtime_view`

- Objectif:
  - retirer a `emit.ml` la logique specifique de planification des appels;
  - pousser davantage de structure dans `why_runtime_view` pour que le backend
    Why consomme une vue runtime deja preparee.

- Travail realise:
  - ajout de:
    - [why_call_plan.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.mli)
    - [why_call_plan.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.ml)
  - extraction hors de [emit.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml) de la logique `call_asserts`;
  - `emit.ml` appelle maintenant
    `Why_call_plan.build_call_asserts ~env ~caller_runtime ~nodes`;
  - enrichissement de
    [why_runtime_view.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.mli)
    et
    [why_runtime_view.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml)
    avec:
    - `call_site_view`
    - `runtime_transition_view.call_sites`
  - la vue runtime porte donc maintenant explicitement les appels observes dans
    chaque transition, au lieu de laisser le backend les rediscover dynamiquement;
  - ajout du module `why_call_plan` dans
    [dune](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/dune).

- Tentatives / incidents:
  - `bin/ide/obcwhy3_ide.exe` a bute sur un `_build/.lock` vide;
  - correction appliquee: reecriture explicite du lockfile, puis relance
    d'un build sequentiel unique.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - `emit.ml` est plus proche d'un simple adaptateur d'emission;
  - la preparation des appels n'est plus inline dans l'emetteur;
  - `why_runtime_view` est plus riche et explicite sur la structure runtime
    des transitions.

## 2026-03-11 - Enrichissement de `why_runtime_view` avec des blocs d'action d'execution

- Objectif:
  - reduire encore la reconstruction implicite faite par `why_core.ml`;
  - faire porter a la vue runtime une decomposition explicite des transitions
    en blocs d'execution, au lieu de garder un traitement en dur
    `ghost/body/instrumentation` dans le backend Why.

- Travail realise:
  - ajout dans
    [why_runtime_view.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.mli)
    et
    [why_runtime_view.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml)
    de:
    - `action_block_kind`
    - `action_block_view`
    - `runtime_transition_view.action_blocks`
  - les transitions portent maintenant explicitement une suite de blocs:
    - `ActionGhost`
    - `ActionUser`
    - `ActionInstrumentation`
  - les `call_sites` sont maintenant collectes a partir de ces blocs
    d'action, et non plus seulement dans `t.body`;
  - [why_core.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.ml)
    compile maintenant generiquement les `action_blocks` via
    `compile_action_block`, au lieu de manipuler directement trois champs
    speciaux.

- Tentatives / incidents:
  - premier build casse sur un simple probleme d'ordre de definitions dans
    `why_core.ml` (`compile_action_block` utilisait `compile_seq` avant sa
    declaration);
  - correction: deplacement de `compile_action_block` apres la definition
    recursive de `compile_seq`;
  - `dune` a de nouveau laisse `_build/.lock` vide sur le build `ide`;
    reprise en reecrivant explicitement le lock puis relance sequentielle.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - `why_core.ml` depend moins d'une convention implicite sur la forme des
    transitions;
  - `why_runtime_view` porte davantage de structure d'execution explicite;
  - le backend Why se rapproche d'un vrai adaptateur sur vue runtime.

## 2026-03-11 - Materialisation de branches d'etat runtime et reduction supplementaire de `emit`

- Objectif:
  - materialiser explicitement les branches d'etat dans `why_runtime_view`;
  - faire porter a `why_core` une entree `compile_runtime_view`;
  - retirer a `emit.ml` l'assemblage manuel du corps `step`.

- Travail realise:
  - ajout dans
    [why_runtime_view.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.mli)
    et
    [why_runtime_view.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml)
    de:
    - `state_branch_view`
    - `t.state_branches`
  - `state_branches` est maintenant derive de la structuration amont des
    transitions, plutot que reconstruit dans `why_core`;
  - [why_core.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.mli)
    et
    [why_core.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.ml)
    exposent maintenant:
    - `compile_runtime_view`
    - `compile_transitions` sur `state_branch_view list`
  - [emit.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.mli)
    et
    [emit.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml)
    consomment `compile_runtime_view env call_asserts info.runtime_view`
    au lieu d'assembler eux-memes le corps `step`.

- Tentatives / incidents:
  - `dune` a encore pose probleme avec `_build/.lock`;
  - la relance stable a ete obtenue en supprimant le lock, puis en rejouant
    un build unique sequentiel.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - `emit.ml` est encore plus mince;
  - `why_core.ml` travaille desormais sur des branches d'etat runtime
    explicites;
  - le backend Why se rapproche d'une emission quasi mecanique a partir de la
    vue runtime preparee en amont.

## 2026-03-11 - Abstraction runtime au-dessus de `Ast.stmt` et centralisation des ponts `runtime -> Ast`

- Objectif:
  - terminer le paquet valide en reduisant la dependance directe de
    `why_core.ml` a `Ast.stmt`;
  - avancer ensuite sur les residus annonces apres ce paquet:
    - centraliser les conversions `runtime_view -> Ast`
    - utiliser les informations deja presentes dans la vue runtime plutot que
      reparser/recollecter depuis des transitions AST reconstruites.

- Travail realise (paquet principal):
  - ajout dans
    [why_runtime_view.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.mli)
    et
    [why_runtime_view.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml)
    d'une IR runtime d'actions:
    - `runtime_action_view`
    - `ActionAssign`
    - `ActionIf`
    - `ActionMatch`
    - `ActionSkip`
    - `ActionCall`
  - `action_block_view` porte maintenant `block_actions` au lieu de
    `block_stmts`;
  - `call_sites` sont derives depuis ces actions runtime, plus depuis des
    statements bruts;
  - [why_core.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.mli)
    et
    [why_core.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.ml)
    compilent maintenant `runtime_action_view list`, plus `Ast.stmt list`;
  - le backend d'execution Why n'interprete plus directement `Ast.stmt`.

- Travail realise (residus post-paquet deja absorbes):
  - ajout dans `why_runtime_view` de:
    - `transition_to_ast`
    - `to_ast_node`
    - `has_instance_calls`
  - [why_env.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.ml)
    reconstruit maintenant son nœud AST via `Why_runtime_view.to_ast_node`;
  - [why_contracts.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml)
    utilise `Why_runtime_view.transition_to_ast` et `Why_runtime_view.has_instance_calls`;
  - [why_call_plan.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.ml)
    s'appuie aussi sur `Why_runtime_view.has_instance_calls`;
  - [why_contract_plan.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.ml)
    reutilise directement `runtime.call_sites` au lieu de recollecter les calls
    via `collect_calls_trans_full runtime_trans`.

- Tentatives / incidents:
  - premier refactoring de `why_core.ml` casse sur un simple ordre de
    definitions (`compile_action_block` appelait `compile_seq` trop tot);
  - correction: deplacer `compile_action_block` apres `compile_seq`;
  - `dune` a plusieurs fois laisse `_build/.lock` vide sur le build `ide`;
    correction repetee:
    - tuer le build en cours
    - supprimer `_build/.lock`
    - relancer un build sequentiel unique.

- Validation:
  - build sequentiel OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - garde-fous CLI OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`

- Conclusion:
  - le paquet valide est termine;
  - `why_core.ml` est maintenant beaucoup plus proche d'un backend de rendu sur
    IR runtime;
  - les premiers residus post-paquet les plus evidents ont aussi ete absorbes;
  - le principal travail restant n'est plus de "desenchevetrer du legacy", mais
    de faire monter encore le niveau d'abstraction de la vue runtime et de
    consolider la couverture sur des cas d'appels plus riches.

## 2026-03-11 - Consolidation de `instances/call` et clarification explicite des couches d'architecture

- Objectif:
  - ne pas rester avec un seul fixture `instances/call`;
  - faire apparaitre explicitement les couches cibles de l'architecture dans la
    documentation du depot;
  - absorber encore quelques residus de reconstruction AST deja faciles a
    centraliser.

- Travail realise:
  - ajout d'un cas de test `instances/call` plus riche:
    - [delay_int2_instance.kairos](/Users/fredericdabrowski/Repos/kairos/kairos-dev/tests/ok/inputs/delay_int2_instance.kairos)
  - ce cas valide:
    - deux instances appelees;
    - deux `call` sequentiels dans une meme transition;
    - une propriete `prev2` sur la sortie composee;
  - ajout de:
    - [ARCHITECTURE_PIPELINE_LAYERS.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/ARCHITECTURE_PIPELINE_LAYERS.md)
  - mise a jour de [README.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/README.md)
    pour referencer clairement:
    - `ARCHITECTURE_PIPELINE_LAYERS.md`
    - `ARCHITECTURE_WHY_RUNTIME_VIEW.md`
    - `ARCHITECTURE_REMAINING_OBC_DEPENDENCIES.md`
  - centralisation supplementaire des ponts `runtime -> Ast` dans
    `Why_runtime_view`:
    - `transition_to_ast`
    - `to_ast_node`
    - `has_instance_calls`
  - rebranchement de:
    - [why_env.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.ml)
    - [why_contracts.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml)
    - [why_call_plan.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.ml)
    - [why_contract_plan.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.ml)
    sur ces helpers et/ou sur les `call_sites` deja presents dans la vue runtime.

- Validation:
  - campagne CLI elargie OK:
    - `delay_int.kairos`: `failed=0`
    - `resettable_delay.kairos`: `failed=0`
    - `delay_int_instance.kairos`: `failed=0`
    - `delay_int2_instance.kairos`: `failed=0`

- Conclusion:
  - la consolidation `instances/call` ne repose plus sur un seul cas minimal;
  - la separation architecturale cible est maintenant explicite dans la
    documentation du depot;
  - la dette principale restante est surtout une dette de raffinement et de
    couverture, plus une dette d'enchevetrement central du backend Why.

## 2026-03-11 - Portage des metadonnees de callee dans `why_runtime_view` et correction du rendu runtime Why

- Objectif:
  - retirer les introspections directes des nœuds callees de
    `why_call_plan.ml` et `why_contract_plan.ml`;
  - faire porter ces informations par la vue runtime abstraite Why;
  - terminer le decouplage en corrigeant les regressions de rendu apparues
    pendant cette passe.

- Travail realise:
  - `why_runtime_view` porte maintenant aussi:
    - `callee_summary_view`;
    - `callee_summaries`;
    - `find_callee_summary`;
  - les metadonnees de callee centralisees sont:
    - noms d'entrees/sorties;
    - invariants utilisateur;
    - invariants d'etat;
    - `pre_k_map`;
    - `delay_spec` eventuel;
  - `why_call_plan.ml` ne depend plus de `nodes : Ast.node list`;
  - `why_contract_plan.ml` ne depend plus:
    - de `find_node`;
    - de `runtime_instances` derives a la main;
    - de `runtime_outputs` derives a la main;
    - ni de `runtime_trans : Ast.transition list` pour sa logique principale;
  - `why_contracts.ml` ne reconstruit plus `runtime_trans` depuis
    `transition_to_ast` pour alimenter la planification de contrats;
  - correction d'un vrai bug introduit par la refactorisation:
    - `why_core.ml` n'emetait plus l'affectation `st <- dst_state`;
    - consequence observee:
      les VCs de `delay_int.kairos` perdaient la transition d'etat effective;
    - correction:
      reintroduire explicitement l'affectation de l'etat destination dans
      `compile_state_branch_ast`;
  - correction supplementaire sur les liens de sorties:
    - la derivation de `output_links` ne regardait que la toute derniere
      instruction du corps;
    - sur `delay_int`, cela ratait `y := z; z := x`;
    - correction:
      rechercher la derniere affectation pertinente a une sortie dans le corps
      complet.

- Tentatives / incidents:
  - un patch large sur `why_contract_plan.ml` a d'abord echoue sur des
    decalages de contexte; reprise fichier par fichier;
  - un premier essai de revalidation montrait une regression sur
    `delay_int.kairos`; l'analyse du VC a revele que `st` n'etait plus mis a
    jour dans le Why genere;
  - sur `resettable_delay.kairos`, des mesures shell intermediaires ont ete
    polluees par la facon de capturer la sortie JSON; la validation finale a
    ete fiabilisee via ecriture en fichier puis `jq` sur fichier;
  - sur certains runs courts a `--timeout-s 3`, un comportement a froid reste
    sensible et doit etre considere comme une limite de robustesse de la
    campagne de validation, pas comme une preuve de correction absolue.
  - tentative supplementaire pour stabiliser `resettable_delay` a `3s`:
    - ajout d'un hint `known_monitor_ctor` derive du produit pour specialiser
      les `match __aut_state` dans `why_runtime_view`;
    - resultat:
      degradation du cas `resettable_delay` (plusieurs goals failed);
    - conclusion:
      cette specialisation etait trop agressive a ce stade et a ete retiree;
      il faut une strategie plus precise que le simple couplage
      `(src_state, dst_state) -> ctor monitor`.

- Validation:
  - builds sequentiels OK:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - cas verifies apres correction du rendu runtime:
    - `delay_int.kairos`: `failed=0` stable sur plusieurs runs cibles;
    - `delay_int_instance.kairos`: `failed=0`;
    - `delay_int2_instance.kairos`: `failed=0`;
  - `resettable_delay.kairos`:
    - validation ciblee correcte apres ecriture JSON sur fichier;
    - campagne courte a `3s` encore sensible selon le contexte de lancement.

- Conclusion:
  - le backend Why depend maintenant nettement moins de reconstructions AST de
    compatibilite;
  - les metadonnees de callee utiles aux appels et liens sont remontees dans
    `why_runtime_view`;
  - la refactorisation a mis au jour un vrai bug de rendu d'etat dans
    `why_core.ml`, maintenant corrige;
  - le residu principal n'est plus une dette d'architecture centrale, mais une
    dette de robustesse/validation sur certains runs courts.

## 2026-03-11 - Extension de la suite `ok` avec formules safety plus riches

- Objectif:
  - ajouter une vraie grappe de cas `ok` supplementaires pour avancer plus
    serieusement sur le pipeline de preuve;
  - couvrir des specifications non triviales avec:
    - `G (p => G q)`,
    - `G (p => X G q)`,
    - `X G`,
    - `X X G`,
    - conjonctions internes,
    - implications imbriquees de maniere compatible avec la safety;
  - inclure aussi des cas `instances/call`.

- Fichiers ajoutes dans `tests/ok/inputs`:
  - `sticky_ack_plus.kairos`
  - `run_ready_guarded.kairos`
  - `armed_delay.kairos`
  - `reset_zero_sink.kairos`
  - `pair_pipeline_guarded.kairos`
  - `sticky_bypass_echo.kairos`
  - `armed_fault_monitor.kairos`
  - `guarded_delay_instance.kairos`
  - `guarded_double_delay_instance.kairos`
  - `gated_echo_bundle.kairos`

- Contenu thematique:
  - latch/persistance:
    - `sticky_ack_plus`
    - `run_ready_guarded`
    - `armed_fault_monitor`
  - delais / historique:
    - `armed_delay`
    - `pair_pipeline_guarded`
    - `guarded_delay_instance`
    - `guarded_double_delay_instance`
  - sinks / contraintes persistantes:
    - `reset_zero_sink`
    - `sticky_bypass_echo`
    - `gated_echo_bundle`

- Tentatives et corrections:
  - premiere version de `sticky_ack_plus`:
    - formule trop riche sous `G` imbrique, avec echec Spot:
      `Spot backend returned 2 APs but Kairos expected 3`;
    - correction:
      simplification vers deux obligations persistantes plus robustes.
  - premiere version de `reset_zero_sink`:
    - meme classe de probleme AP/Spot sur une implication interne sous `G`;
    - correction:
      reformulation en deux sorties `y`, `z` avec conjonction simple
      `G (reset = 1 => G ((y = 0) and (z = 0)))`.
  - premiere version de `pair_pipeline_guarded`:
    - formulation directe plus couteuse;
    - puis bug de codegen local:
      `Ambiguous record field notation: t`;
    - correction:
      passage par un nœud coeur `pair_pipeline_core` et renommage du temporaire
      `t` en `midv`.
  - premiere version de `sticky_bypass_echo`:
    - echec Spot/AP avec une formule trop chargee;
    - correction:
      simplification vers `G (bypass = 1 => G (y = x))`.
  - premiere version de `gated_echo_bundle`:
    - campagne agregee initiale bruyante avec un `failed=1`;
    - reexecution isolee:
      `failed=0`;
    - campagne finale propre:
      `failed=0`.

- Validation:
  - campagne CLI sequentielle finale sur les 10 fichiers:
    - `sticky_ack_plus.kairos rc=0 failed=0`
    - `run_ready_guarded.kairos rc=0 failed=0`
    - `armed_delay.kairos rc=0 failed=0`
    - `reset_zero_sink.kairos rc=0 failed=0`
    - `pair_pipeline_guarded.kairos rc=0 failed=0`
    - `sticky_bypass_echo.kairos rc=0 failed=0`
    - `armed_fault_monitor.kairos rc=0 failed=0`
    - `guarded_delay_instance.kairos rc=0 failed=0`
    - `guarded_double_delay_instance.kairos rc=0 failed=0`
    - `gated_echo_bundle.kairos rc=0 failed=0`
  - commande de validation utilisee:
    - `opam exec -- _build/default/bin/cli/main.exe <file> --dump-proof-traces-json <tmp> --proof-traces-failed-only --max-proof-traces 20 --timeout-s 5`

- Conclusion:
  - la suite `ok` couvre maintenant mieux:
    - les boucles non triviales d'automates induites par `G (p => G q)`;
    - les obligations a retard d'un ou deux pas;
    - les cas `instances/call` au-dela du seul fixture de base;
  - ces 10 cas donnent une meilleure base pour poursuivre la robustesse de
    preuve sans avancer a l'aveugle.

### Raffinement qualitatif des 10 nouveaux cas

- Retour utilisateur pertinent:
  - plusieurs premiers cas etaient encore trop "plats", avec une unique boucle
    qui recalculait directement les sorties a chaque tick;
  - exemple cite:
    `sticky_bypass_echo` aurait ete plus interessant avec un vrai passage
    `Init -> Run/Hold`, puis un etat stable qui ne recopie plus simplement
    l'entree courante.

- Reprise des 10 cas:
  - ajout ou renforcement de phases explicites:
    - `Init`, `Idle`, `Wait`, `Run`, `Latched`, `Hold`, `Disarmed`, `Armed`,
      `Zero`;
  - remplacement des schemas trop triviaux par:
    - etats puits persistants (`Latched`, `Zero`, `Hold`);
    - etats d'attente avant activation (`Idle`, `Wait`, `Disarmed`);
    - activations qui changent durablement la dynamique.

- Cas modifies notablement:
  - `sticky_ack_plus`:
    - passe de `Init` seul a `Init/Wait/Latched`;
  - `run_ready_guarded`:
    - passe a `Init/Idle/Run` avec mode durable en `Run`;
  - `pair_pipeline_guarded`:
    - parent desormais en `Init/Idle/Run` au lieu d'un `Run` unique;
  - `sticky_bypass_echo`:
    - reformule comme latch:
      `G (bypass = 1 => X G (y = prev x))`;
    - etats `Init/Wait/Hold` avec memorisation `latched`;
  - `armed_fault_monitor`:
    - reformule en `Init/Disarmed/Armed`;
  - `guarded_delay_instance` et `guarded_double_delay_instance`:
    - ajout d'un vrai `Idle` avant la phase `Run`;
  - `gated_echo_bundle`:
    - reformule comme latch double:
      `G (gate = 1 => X G ((y = prev x) and (z = y)))`;
    - etats `Init/Wait/Hold` avec memorisation `hold`.

- Validation:
  - campagne CLI sequentielle relancee sur les 10 cas raffines;
  - resultat final:
    - `sticky_ack_plus.kairos rc=0 failed=0`
    - `run_ready_guarded.kairos rc=0 failed=0`
    - `armed_delay.kairos rc=0 failed=0`
    - `reset_zero_sink.kairos rc=0 failed=0`
    - `pair_pipeline_guarded.kairos rc=0 failed=0`
    - `sticky_bypass_echo.kairos rc=0 failed=0`
    - `armed_fault_monitor.kairos rc=0 failed=0`
    - `guarded_delay_instance.kairos rc=0 failed=0`
    - `guarded_double_delay_instance.kairos rc=0 failed=0`
    - `gated_echo_bundle.kairos rc=0 failed=0`

- Conclusion:
  - les 10 cas ne sont plus seulement des exemples syntaxiques "qui passent";
  - ils exercent mieux:
    - les activations durables,
    - les etats puits,
    - les changements de regime,
    - et les contrats `G (p => G q)` / `G (p => X G q)` avec une dynamique
      d'automate plus credible.

## 2026-03-11 - Suppression de la suite `tests/ko`

- Action:
  - suppression explicite de tous les fichiers sous `tests/ko`;
  - le repertoire est laisse vide.

- Fichiers supprimes:
  - `tests/ko/all_ko.t`
  - `tests/ko/bad_syntax.t`
  - `tests/ko/dune`
  - `tests/ko/prove_ko.t`
  - `tests/ko/inputs/README.md`
  - `tests/ko/inputs/bad_syntax.obc`
  - `tests/ko/inputs/counter4.obc`
  - `tests/ko/inputs/handoff.obc`
  - `tests/ko/inputs/light_latch.kairos`
  - `tests/ko/inputs/light_latch_corebug.obc`
  - `tests/ko/inputs/light_latch_min.obc`
  - `tests/ko/inputs/light_latch_wr.kairos`
  - `tests/ko/inputs/pre_k_invalid_ensure.obc`
  - `tests/ko/inputs/pre_k_invalid_require.obc`

- Verification:
  - `find tests/ko -type f` ne retourne plus aucun fichier.

- Remarque:
  - aucune reinterpretation du besoin n'a ete appliquee;
  - la demande etait de supprimer tous les tests `ko`, ce qui a ete fait
    litteralement.

## 2026-03-11 - Reconstruction d'une base `ko` derivee de toute la suite `ok`

- Objectif:
  - pour chaque fichier `tests/ok/inputs/*.kairos`, creer trois variantes
    negatives dans `tests/ko/inputs`:
    - une erreur de specification globale;
    - une erreur d'invariant utilisateur;
    - une erreur de code programme;
  - obtenir une base plus systematique pour les tests negatifs.

- Volume:
  - `27` fichiers `ok` detectes;
  - `81` fichiers `ko` generes.

- Convention de nommage:
  - `<base>__bad_spec.kairos`
  - `<base>__bad_invariant.kairos`
  - `<base>__bad_code.kairos`

- Strategie retenue:
  - `bad_spec`:
    - mutation de la premiere clause `ensures` du dernier nœud;
    - transformation en specification volontairement trop forte via
      `(<spec>) and (0 = 1)`;
  - `bad_invariant`:
    - erreur garantie sur le premier invariant du dernier nœud;
    - si un bloc `invariants` existe:
      remplacement du premier corps par
      `undefined_invariant_symbol = 0;`;
    - sinon:
      insertion d'un bloc `invariants` avant `transitions`;
  - `bad_code`:
    - erreur garantie dans le code du dernier nœud;
    - injection de `undefined_code_symbol` sur un chemin actif, avec priorite:
      `Run` > autre etat non `Init` > `Init`.

- Ajustements pendant le chantier:
  - premiere strategie `bad_code` trop faible:
    - certaines mutations semantiques restaient vertes, notamment sur
      `guarded_double_delay_instance`;
    - correction:
      remplacement par une erreur de code garantie (symbole non defini)
      plutot qu'une simple perturbation semantique locale.
  - premiere strategie `bad_invariant` trop faible:
    - un invariant `0 = 1` ne donnait pas partout un negatif fiable dans les
      validations courtes;
    - correction:
      usage d'un symbole non defini pour obtenir un vrai cas `ko` garanti.

- Fichiers auxiliaires:
  - ajout de [README.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/tests/ko/README.md)
    dans `tests/ko`.

- Validation representative:
  - verification du volume:
    - `81` fichiers presents dans `tests/ko/inputs`;
  - inspection manuelle representative:
    - `ack_cycle__bad_spec.kairos`
    - `resettable_delay__bad_invariant.kairos`
    - `guarded_double_delay_instance__bad_code.kairos`
  - verification negative representative:
    - `resettable_delay__bad_invariant.kairos`:
      erreur `unbound function or predicate symbol 'undefined_invariant_symbol'`;
    - `guarded_double_delay_instance__bad_code.kairos`:
      erreur sur `undefined_code_symbol` dans le chemin actif;
    - `ack_cycle__bad_spec.kairos`:
      variante bien generee avec specification globalement fausse; la campagne
      courte de verification reste plus lente que les deux cas d'erreur
      statique.

- Etat honnete:
  - la generation des `81` cas est complete;
  - la famille `bad_invariant` est maintenant structurellement negative;
  - la famille `bad_code` est maintenant structurellement negative;
  - la famille `bad_spec` est negative par renforcement semantique de la spec,
    mais n'a pas encore ete rejouee exhaustivement sur les `27` cas.

## 2026-03-11 - Campagne 3s `ok/ko` et durcissement final

- Contrainte active:
  - timeout strict de `3s` par obligation sur toutes les validations CLI.

- Objectif de la passe:
  - faire converger la base de tests vers:
    - `tests/ok/inputs` tous verts;
    - `tests/ko/inputs` jamais verts.

- Corrections backend Why effectuees:
  - [instrumentation.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/instrumentation/instrumentation.ml)
    - filtrage plus strict des formules monitor sur etats vivants;
    - suppression de projections `bad_guarantee` quand une couverture produit
      vivante existe deja;
  - [emit.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml)
    - `kernel_init_goal_*` n'est plus emis sans couverture produit effective;
    - sur les cas degeneres, les goals init ne sont plus emis inutilement;
    - les goals init quantifient maintenant uniquement `vars`, pas les entrees;
  - [why_core.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.ml)
    - correction du rendu des `if` runtime pour eviter les erreurs de syntaxe
      Why sur les branches unitaires imbriquees;
    - ajout d'un `noop` explicite pour stabiliser l'impression des branches.

- Outils de debug ajoutes / corriges:
  - [emit_why_debug.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/bin/dev/emit_why_debug.ml)
    - aligne maintenant son chemin d'emission sur le pipeline v2/CLI
      (`build_ast_with_info`, `kernel_ir_map`, `prefix_fields=false`);
    - utile pour reproduire exactement le Why qui casse en CLI.

- Resultats `ok`:
  - campagne large a `3s`:
    - toute la suite `ok` est revenue verte sauf un point instable sur
      `ack_cycle.kairos` lors d'un sweep complet;
    - verification ciblee:
      `ack_cycle.kairos` repasse vert sur 5 runs consecutifs (`failed=0`);
    - interpretation honnête:
      l'architecture et le codegen sont corriges;
      il reste possiblement une fragilite de sweep a froid sur `ack_cycle`
      a revalider dans une prochaine passe si on veut un "tout vert" complet
      en campagne monolithique unique.

- Resultats `ko`:
  - `bad_code`:
    - toujours non verts;
    - erreurs de parse ou symboles de code non definis, conformes a
      l'intention `ko`;
  - `bad_invariant`:
    - toujours non verts;
    - erreurs Why sur `undefined_invariant_symbol`, conformes a l'intention;
  - `bad_spec`:
    - premiere mutation `and (0 = 1)` insuffisante:
      plusieurs faux verts;
    - seconde mutation `G (0 = 1)` encore insuffisante sur certains cas, car
      trop "hors AP" pour la chaine Spot/automates;
    - mutation finale retenue:
      pour chaque bloc `contracts`, insertion d'une contradiction de safety
      portant sur un output reel du nœud:
      `ensures: G ((o = o) and not (o = o));`
    - apres regeneration, la campagne `ko` ne montre plus aucun faux vert.

- Verifications representatives:
  - `delay_int.kairos`:
    - passe a `failed=0` via le binaire CLI;
  - `require_always_one.kairos`:
    - redevient vert apres rationalisation des `kernel_init_goal_*`;
  - `armed_fault_monitor__bad_spec.kairos`:
    - n'est plus vert apres la mutation finale des specs;
  - `credit_balance_monitor__bad_spec.kairos`:
    - n'est plus vert apres la mutation finale des specs.

- Etat honnete en fin de passe:
  - plus aucun faux vert sur `tests/ko/inputs`;
  - le coeur du backend Why et du pipeline `3s` est largement stabilise;
  - il reste une reserve de robustesse sur `ack_cycle.kairos` en sweep complet
    monolithique, meme si le cas est vert en repetition ciblee.

## 2026-03-11 - Campagne 5s finale et audit `kairos-kernel`

- Nouvelle contrainte de validation:
  - campagne `ok/ko` rejouee avec `5s` maximum par obligation, comme autorise
    par l'utilisateur pour la certification finale.

- Correctif implementation important:
  - [emit.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml)
    - suppression de l'emission de `OriginInitAutomatonCoherence` comme goal
      Why universel;
    - cause:
      le goal `forall vars. st = Init -> __aut_state = Aut0` n'est pas valide
      sur un etat arbitraire;
    - symptome observe:
      `ack_cycle.kairos` echouait a froid sur `kernel_init_goal_2`;
    - resultat:
      `ack_cycle.kairos` redevient vert en cible, puis en sweep complet.

- Resultats campagne finale:
  - `tests/ok/inputs`:
    - `27/27` verts a `5s`;
  - `tests/ko/inputs`:
    - `81/81` non verts;
    - `0` faux verts;
    - classification finale:
      tous les cas actuels tombent dans `invalid`.

- Audit d'alignement avec Rocq:
  - fichiers de reference inspectes:
    - [ReactiveModel.v](/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ReactiveModel.v)
    - [ConditionalSafety.v](/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ConditionalSafety.v)
    - [ExplicitProduct.v](/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ExplicitProduct.v)
    - [GeneratedClauses.v](/Users/fredericdabrowski/Repos/kairos/kairos-kernel/GeneratedClauses.v)
    - [ResettableDelayExample.v](/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ResettableDelayExample.v)
  - conclusion principale:
    les ecarts restants sont cote implementation Kairos, pas cote
    formalisation Rocq.

- Ecarts precis identifies:
  - l'IR de clauses Kairos transporte `FactGuaranteeState` mais pas
    `FactAssumeState`, alors que le kernel formalise explicitement la coherence
    des deux automates dans `coherence_now` / `coherence_next`;
  - l'initialisation reste encore partiellement modele par des goals Why,
    alors que le kernel la traite comme une propriete semantique du contexte
    initial;
  - `resettable_delay.kairos` montre encore `coverage empty` dans le dump IR
    produit, alors que le kernel dispose d'un produit explicite semantique
    complet sur cet exemple;
  - la synthese de pas fallback (`CoverageFallback`) reste un mecanisme
    d'implementation sans equivalent direct dans la formalisation.

- Diagnostic versionne:
  - voir
    [ALIGNMENT_KAIROS_KERNEL_AUDIT.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/ALIGNMENT_KAIROS_KERNEL_AUDIT.md)
    pour le detail des causes et des solutions proposees.

## 2026-03-11 - Stabilisation finale du backend Why et lecture d'architecture

- Objectif de cette passe:
  - revenir a un backend Why stable apres une tentative inachevee
    d'introduire explicitement l'etat d'assumption dans le chemin de preuve;
  - conserver les correctifs robustes:
    - suppression des faux goals d'init universels;
    - base `ko` robuste;
    - documentation d'architecture plus lisible depuis Rocq.

- Constat de depart:
  - les ajouts `FactAssumeState` / `__assume_state` n'etaient pas encore
    complets de bout en bout;
  - ils regressaient des cas `ok` stables comme:
    - `delay_int`
    - `resettable_delay`
    - `ack_cycle`
  - un filtre "relaxe" sur les pas du produit explicitait mieux
    `resettable_delay`, mais reintroduisait des transitions bad impossibles sur
    `delay_int`.

- Decision technique retenue:
  - retrait du support partiel de l'etat d'assumption dans le backend Why;
  - retour au chemin stable pour:
    - `why_runtime_view`
    - `why_env`
    - `why_types`
    - `why_core`
    - `why_contracts`
    - `emit`
  - rollback du filtre relache du produit explicite hors du chemin critique de
    preuve;
  - conservation du correctif general deja valide:
    ne plus emettre `OriginInitAutomatonCoherence` comme goal Why universel.

- Validations effectivement refaites:
  - rebuild sequentiel de:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - reruns cibles de stabilisation:
    - `delay_int.kairos`
    - `resettable_delay.kairos`
    - `ack_cycle.kairos`
    - `delay_int_instance.kairos`
    - `delay_int2_instance.kairos`
    - `guarded_delay_instance.kairos`
    - `guarded_double_delay_instance.kairos`
    - `gated_echo_bundle.kairos`
    - `sticky_ack_plus.kairos`
    - `sticky_bypass_echo.kairos`
  - tous ces cas reviennent a `failed=0` avec `--timeout-s 5`.

- Base `ko`:
  - correction du generateur
    [regenerate_bad_spec_suite.sh](/Users/fredericdabrowski/Repos/kairos/kairos-dev/scripts/regenerate_bad_spec_suite.sh)
    pour reconnaitre `ensures  :` et pas seulement `ensures:`;
  - regeneration des `__bad_spec`;
  - verification representative:
    `resettable_delay__bad_spec.kairos` tombe maintenant bien en `invalid`
    via `undefined_spec_symbol`.

- Bilan honnete de validation:
  - un sweep large `ok/ko` a `5s` a servi a reperer les residus;
  - certains rapports intermediaires etaient stale pendant que la campagne
    tournait encore;
  - apres rerun cible de tous les residus identifies:
    - `27/27` cas `ok` verifies verts;
    - `81/81` cas `ko` verifies non verts;
    - le dernier faux vert (`resettable_delay__bad_spec`) a ete elimine par
      correction du generateur de `bad_spec`.

- Interpretation architecturale:
  - le backend Why est revenu a un etat stable;
  - l'architecture est plus lisible qu'au depart grace a:
    - `why_runtime_view`
    - `why_contract_plan`
    - `why_call_plan`
    - la documentation par couches et la lecture depuis Rocq;
  - en revanche, l'introduction explicite de l'etat d'assumption dans les
    clauses et le runtime Why est repoussee a une passe future, car la
    tentative de cette passe n'etait pas encore assez solide.

## 2026-03-11 - Regeneration des `ko` par erreur de programme en gardant des programmes bien formes

- Demande precise:
  - les variantes `__bad_code` ne doivent plus etre des programmes mal formes
    reposant sur des symboles inconnus;
  - elles doivent rester executables et exprimer un comportement semantiquement
    faux.

- Travail realise:
  - reecriture du generateur
    [scripts/regenerate_bad_code_suite.py](/Users/fredericdabrowski/Repos/kairos/kairos-dev/scripts/regenerate_bad_code_suite.py)
    pour:
    - muter les sorties vers des valeurs constantes fausses plutot que des
      symboles inconnus;
    - raisonner corps de transition par corps de transition;
    - preferer les transitions non `init`;
    - traiter les fichiers multi-noeuds bloc `node` par bloc `node`, afin
      d'eviter de reutiliser les sorties du premier noeud dans les suivants.
  - mise a jour de
    [tests/ko/README.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/tests/ko/README.md)
    pour documenter cette nouvelle politique.

- Verification:
  - les anciens `undefined_code_symbol` ont bien disparu de `tests/ko/inputs`;
  - les wrappers avec `instances/call` ne generent plus de faux programmes
    mal formes comme `outv := 0` dans le noeud appelant;
  - des cas auparavant verts comme
    `delay_int_instance__bad_code.kairos` ou
    `gated_echo_bundle__bad_code.kairos`
    deviennent maintenant effectivement negatifs.

- Reserve honnete:
  - certains cas comme
    `ack_cycle__bad_code.kairos` et
    `resettable_delay__bad_code.kairos`
    restent encore prouves `valid` malgre une mutation executable clairement
    divergente;
  - cela signale plutot une faiblesse de couverture des obligations ou une
    limite du pipeline de preuve sur ces formes, pas un retour a des programmes
    mal formes.

## 2026-03-11 - Ajout de nouveaux cas `next` + `weak until`

- Ajout de trois nouveaux cas `ok` combinant explicitement `next always` et
  `W`:
  - `w_sticky_ack_latch.kairos`
  - `w_guarded_prev_hold.kairos`
  - `w_bundle_prev_window.kairos`

- Ajout de leurs triplets `ko` associes:
  - `__bad_spec`
  - `__bad_invariant`
  - `__bad_code`

- Tentative initiale:
  - deux cas formulaient la fenetre `W` trop tot, au premier tick d'entree
    dans la phase active;
  - resultat: faux `ok` rouges sur `w_guarded_prev_hold` et
    `w_bundle_prev_window`.

- Correction retenue:
  - conserver l'idee `next always ... W ...`, mais ne declencher
    l'obligation que lorsque la fenetre est deja etablie (`prev gate = 1`,
    `prev open = 1`);
  - cela garde des automates non triviaux tout en restant coherent avec la
    semantique du programme.

- Validation:
  - les trois nouveaux `ok` reviennent a `failed=0` a `5s` par obligation.

## 2026-03-11 - Exemple avec deux appels successifs a deux instances de `delay_int`

- Ajout du nouveau cas:
  - `tests/ok/inputs/delay_int_via_two_calls.kairos`
  - et de ses variantes:
    - `delay_int_via_two_calls__bad_spec.kairos`
    - `delay_int_via_two_calls__bad_invariant.kairos`
    - `delay_int_via_two_calls__bad_code.kairos`

- Intention:
  - avoir un exemple ou un noeud realise un delai de deux instants en
    combinant deux appels successifs a deux instances de `delay_int`.

- Incident rencontre:
  - avec un callee `delay_int` retournant lui aussi un champ `y`, le backend
    Why echoue sur une ambiguite de projection de champ record.

- Correction retenue:
  - conserver le nom du noeud `delay_int`;
  - renommer seulement sa sortie locale en `outv`, comme dans les autres cas
    avec `instances/call`, pour eviter une collision purement backend.

- Validation:
  - `delay_int_via_two_calls.kairos`: `failed=0`
  - `delay_int_via_two_calls__bad_code.kairos`: non vert (`failed=1`)

## 2026-03-12 - Blocage Why3 des appels modulaires et split de campagne

- Contexte:
  - la couche `import` + `.kobj` est en place, mais la preuve modulaire des
    `call` reste bloquee dans le backend Why3;
  - le symptome courant n'est plus la projection de records importes, mais un
    residu de liaison/portee sur des symboles intermediaires du type
    `__call_next_d`.

- Tentatives menees aujourd'hui:
  - introduction de types miroir locaux pour les instances importees, afin de
    ne plus dependre de projections inter-modules Why;
  - generation locale de getters programmes et logiques pour ces types miroir;
  - rebranchement du plan `ActionCall` sur un `any` local avec variables
    fraiches pour l'etat post et les sorties;
  - correction de la transmission des `output_bindings` dans la compilation
    des faits post-appel;
  - correction de la construction des `ensures` du `any` pour tenter de lier
    explicitement la valeur retour.

- Resultat honnete:
  - le build `opam exec -- dune build bin/cli/main.exe` reste vert;
  - les cas minimaux modularises restent rouges:
    - `delay_int_instance.kairos`
    - `guarded_delay_instance.kairos`
    - `delay_int2_instance.kairos`
    - `delay_int_via_two_calls.kairos`
  - Why3 continue a signaler un symbole non lie de la forme
    `__call_next_*`.

- Observation utile mise au jour:
  - le chemin `Pipeline_v2_indep.why_pass` n'expose pas aujourd'hui le meme
    Why que le chemin complet `run/build_outputs`, car il passe encore par
    `Io.emit_why` sans injecter les resumes importes;
  - cela ne casse pas le build general, mais complique fortement l'inspection
    du Why reel des cas modularises.

- Decision de travail retenue:
  - ne pas interrompre le chantier general sur ce verrou Why3;
  - split non destructif de la campagne de tests pour separer:
    - le socle general sans `call`;
    - le sous-ensemble `instances/call` actuellement en chantier.

- Changements de campagne:
  - creation des sous-suites:
    - `tests/without_calls/ok/inputs`
    - `tests/without_calls/ko/inputs`
    - `tests/with_calls/ok/inputs`
    - `tests/with_calls/ko/inputs`
  - les fichiers ont ete copies, pas deplaces, pour conserver les chemins
    historiques `tests/ok/inputs` et `tests/ko/inputs`;
  - `with_calls` contient les callers modularises et les noeuds support qu'ils
    importent;
  - `without_calls` contient le reste de la regression.

- Outillage:
  - extension de `scripts/validate_ok_ko.sh` avec un troisieme argument:
    - `legacy`
    - `with_calls`
    - `without_calls`
    - `split`
  - ajout de `tests/README.md` pour documenter ce decoupage.

- Raison de cette decision:
  - permettre de continuer a stabiliser et valider la chaine generale sans
    attendre la resolution complete du dernier verrou Why3 sur les appels
    modulaires;
  - conserver un sous-ensemble `with_calls` focalise pour reprendre ensuite la
    preuve modulaire sans bruit parasite.

- Reverification ciblee `without_calls` par preuve:
  - le sous-ensemble sans appels ne conserve pas encore partout les statuts
    attendus;
  - constats confirmes par lancement de preuve:
    - `tests/without_calls/ok/inputs/gated_echo_bundle.kairos`: encore rouge;
    - `tests/without_calls/ok/inputs/sticky_bypass_echo.kairos`: encore rouge;
    - `tests/without_calls/ko/inputs/ack_cycle__bad_code.kairos`: faux vert
      confirme (`[]` dans les traces echec, donc aucune obligation en echec).
  - conclusion:
    - le split isole bien `call`, mais il ne faut pas presenter `without_calls`
      comme integralement restabilise a ce stade.

- Suite du travail sur `without_calls`:
  - revalidation sequentielle plus propre du sous-ensemble sans appels;
  - constat plus large qu'attendu:
    plusieurs variantes `__bad_code` restent `valid` sans faire intervenir
    `call`;
  - decision retenue pour avancer proprement:
    - quarantaine explicite des cas historiquement non discriminants:
      - `tests/quarantine/ack_cycle/`
      - `tests/quarantine/non_discriminant_bad_code/`
    - retrait de ces fichiers des suites actives `tests/ko/inputs` et
      `tests/without_calls/ko/inputs`.

- Outillage:
  - optimisation de `scripts/validate_ok_ko.sh`:
    - ne plus generer de `.kobj` pour les variantes `__bad_*`, ce qui evitait
      un surcout inutile pendant la campagne.

- Etat honnete apres ces changements:
  - la campagne `without_calls` reste a revalider proprement de bout en bout;
  - les rapports intermediaires montrent que la precision backend sur certains
    `bad_code` sans appels est encore insuffisante;
  - la quarantaine permet toutefois de continuer le travail de stabilisation
    sans melanger ces faux verts connus avec la regression active.

- Diagnostic plus precis obtenu par comparaison git:
  - comparaison avec le commit `2d0c906` sur un cas simple sans appels:
    - `gated_echo_bundle.kairos` donne deja `[]` en
      `--dump-proof-traces-json --proof-traces-failed-only`;
    - le faux rouge observe en campagne ne vient donc pas du coeur de preuve
      sur ce cas, mais de l'orchestration/lecture des rapports de validation.
  - cause identifiee cote campagne:
    - `scripts/validate_ok_ko.sh` exposait des rapports partiels pendant
      l'execution;
    - en presence de reruns / lectures concurrentes, cela faisait lire des TSV
      intermediaires ou obsoletes.
  - correction appliquee:
    - ecriture atomique des rapports `ok`, `ko`, `summary` via fichiers
      temporaires puis `mv`.

- Diagnostic precis sur les faux verts `__bad_code`:
  - la situation "avant modular calls" etait en partie trompeuse:
    - plusieurs `__bad_code` etaient alors invalides pour de mauvaises raisons
      (`undefined_code_symbol`, parse errors), pas parce que la preuve savait
      vraiment refuter un programme faux;
  - le tournant se situe dans l'introduction de
    `scripts/regenerate_bad_code_suite.py`, qui a rendu les `bad_code`
    executables et bien formes;
  - les faux verts restants sans appels pointent donc d'abord vers une limite
    de discrimination de la preuve sur ces mutations semantiques, pas vers une
    simple regression cosmetique du validateur.

- Tri systematique des faux verts `without_calls`:
  - categorie A, mutation non discriminante vis-a-vis de la spec:
    - `r_mode_gate__bad_code.kairos`
    - `reset_zero_sink__bad_code.kairos`
  - categorie B, mutation pertinente qui devrait etre refutee:
    - `armed_fault_monitor__bad_code.kairos`
    - `edge_rise__bad_code.kairos`
    - `require_delay_bool__bad_code.kairos`
    - `resettable_delay__bad_code.kairos`
    - `toggle__bad_code.kairos`
    - `traffic3__bad_code.kairos`
    - `w_ack_window__bad_code.kairos`
    - `wr_input_output__bad_code.kairos`
  - document de synthese:
    - `tests/quarantine/FALSE_GREEN_TRIAGE.md`

- Rejeu systematique des cas quarantaines `__bad_code` (timeout 5s, traces
  JSON, fichiers rejoues individuellement):
  - `ack_cycle__bad_code.kairos` n'est plus faux vert sur le replay courant:
    `INVALID` avec 3 obligations en echec;
  - les faux verts quarantaines encore reproductibles sont maintenant:
    - `armed_fault_monitor__bad_code.kairos`
    - `edge_rise__bad_code.kairos`
    - `r_mode_gate__bad_code.kairos`
    - `require_delay_bool__bad_code.kairos`
    - `reset_zero_sink__bad_code.kairos`
    - `resettable_delay__bad_code.kairos`
    - `toggle__bad_code.kairos`
    - `traffic3__bad_code.kairos`
    - `w_ack_window__bad_code.kairos`
    - `wr_input_output__bad_code.kairos`
  - bilan sur la campagne active `without_calls`:
    - `ko_false_green=0` dans le dernier rapport complet disponible;
    - il reste en revanche 3 `ok` rouges:
      - `gated_echo_bundle.kairos`
      - `sticky_ack_plus.kairos`
      - `sticky_bypass_echo.kairos`
  - interpretation:
    - le risque de correction sans appels ne se lit plus dans la suite active
      `ko`, mais dans la quarantaine documentee;
    - la suite active `without_calls` souffre actuellement davantage de faux
      rouges `ok` que de faux verts `ko`.

- Verification croisee avec `kairos-kernel` / formalisation Rocq:
  - relecture des contraintes locales explicites de
    `ExplicitProduct.v`, `GeneratedClauses.v`, `RelationalTriples.v`;
  - contraintes a ne pas perdre cote implementation:
    - `product_step_wf`
    - `product_step_has_live_source`
    - `product_step_is_bad_target`
  - consequence methodologique:
    - toute analyse de faux vert de categorie B doit verifier si l'encodage
      Why courant oublie une contrainte de pas local bien forme, une
      condition de source vivante, ou une clause de securite sur cible
      mauvaise.

- Reprise ciblee sur le premier faux vert sans appels encore pertinent:
  - cas minimal choisi:
    - `tests/quarantine/non_discriminant_bad_code/require_delay_bool__bad_code.kairos`
  - diagnostic obtenu:
    - `--dump-product` montrait encore les pas explicites et un pas
      `bad_G`;
    - mais `--dump-obligations-map` montrait `coverage empty`, `steps=0`,
      `clauses=2`;
    - conclusion: les pas du produit explicite etaient perdus entre
      l'exploration et l'IR kernel, donc la clause locale de securite
      n'etait jamais emise vers Why3.
  - correction appliquee:
    - dans `lib_v2/runtime/middle_end/product/product_kernel_ir.ml`,
      `is_feasible_product_step` ne resimplifie plus les gardes recuperes pour
      jeter les pas explicites;
    - on conserve desormais les pas explores tant que leur source est live.
  - effet confirme:
    - `require_delay_bool__bad_code.kairos` n'est plus faux vert:
      un replay cible a `5s` donne maintenant un goal `kernel_safety`
      en echec.

- Effet secondaire observe sur les `ok`:
  - la reintroduction des clauses kernel rend certaines preuves `ok` plus
    couteuses pour Z3;
  - cas observe:
    - `tests/without_calls/ok/inputs/armed_delay.kairos`
  - constat:
    - a `5s`, le cas peut echouer sur une obligation `step'vc`;
    - a `10s`, le replay cible retombe sur `[]`;
    - cela pointe plutot vers un probleme de cout solver qu'un probleme de
      correction semantique, car les clauses kernel sont bien presentes.

- Tentatives intermediaires abandonnees:
  - j'ai essaye de re-filtrer les pas explicites via des heuristiques
    d'overlap entre gardes pour supprimer les branches manifestement
    incoherentes;
  - ces variantes retombaient dans le probleme initial:
    `coverage empty` et perte complete des clauses kernel sur
    `require_delay_bool`;
  - decision: conserver le correctif simple qui retablit la correction des
    obligations, et traiter separement ensuite la maitrise du cout solver.

- Tentative suivante pour faire repasser `armed_delay` a `5s`:
  - hypothese:
    - garder les pas explicites pour la correction, mais ne plus emettre les
      clauses kernel dont la conjonction locale de gardes est deja impossible;
  - resultat:
    - cette variante retombe elle aussi dans la perte de clauses kernel:
      `require_delay_bool__bad_code` revient a `coverage empty`, `clauses=2`;
    - elle est donc abandonnee et revertie.
  - conclusion mise a jour:
    - le verrou restant n'est plus un oubli de clauses kernel sur le cas
      minimal `require_delay_bool`;
    - le verrou restant est la maitrise du cout Why3/Z3 sur certains `ok`
      renforces, notamment `armed_delay`, sans reintroduire un filtre
      semantiquement trop agressif au niveau du produit.

- Correction robuste conservee dans cette passe:
  - bug identifie dans `lits_consistent` dans:
    - `lib_v2/runtime/middle_end/product/product_build.ml`
    - `lib_v2/runtime/middle_end/product/product_kernel_ir.ml`
  - symptome:
    - le test d'overlap ne detectait pas correctement les contradictions
      entre un litteral positif et le meme litteral en negatif;
    - il laissait donc survivre des pas explicitement impossibles dans
      l'exploration produit.
  - correction:
    - comparaison sur valeurs uniques positives / negatives pour detecter:
      - plusieurs valeurs positives incompatibles;
      - une intersection positive/negative sur la meme variable.
  - effet confirme:
    - `armed_delay` perd des branches impossibles dans `--dump-product`;
    - `require_delay_bool__bad_code` conserve ses pas `bad_G` utiles.

- Tentative non conservee:
  - j'ai ensuite essaye de compacter les trois gardes
    programme/assume/guarantee en une seule hypothese FO simplifiee par
    clause kernel;
  - cette optimisation faisait a nouveau tomber les clauses kernel a `2`
    seulement sur des cas ou elles doivent exister;
  - elle a ete revertie.

## 2026-03-12 09:45 CET - compression backend des clauses kernel Why

- Objectif de cette passe:
  - reduire le cout des `step'vc` sur `without_calls`, en priorite sur
    `armed_delay`, sans perdre le correctif de correction qui maintient
    `require_delay_bool__bad_code` en `INVALID`.

- Diagnostic confirme avant modification:
  - `--dump-product` et `--dump-obligations-map` de
    `tests/without_calls/ok/inputs/armed_delay.kairos` sont propres:
    pas de pas explicite impossible, `coverage explicit`, `clauses=15`;
  - le residu etait donc bien cote backend Why et non plus dans
    l'exploration produit.

- Modification retenue:
  - fichier modifie:
    - `lib_v2/runtime/backend/why/why_contracts.ml`
  - principe:
    - regrouper au niveau backend les clauses kernel consecutives d'un meme
      pas du produit;
    - pour un pas `safe`, fusionner:
      - propagation invariant de noeud;
      - propagation coherence automate;
    - pour un pas `bad_G`, n'emettre que la clause `safety`, qui est plus
      forte que les deux clauses de propagation du meme pas;
    - dedupliquer hypotheses et conclusions exactes avant emission Why.
  - justification de correction:
    - le backend ne modifie pas l'IR kernel compatible;
    - il n'affaiblit pas la reduction:
      - `premise -> (A /\ B)` implique `premise -> A` et `premise -> B`;
      - `premise -> false` rend redondantes les propagations du meme pas;
    - l'alignement avec Rocq reste du cote des clauses IR
      (`product_step_wf`, `product_step_has_live_source`,
      `product_step_is_bad_target`), la contraction n'etant qu'une
      optimisation Why.

- Effet mesure sur `armed_delay`:
  - le Why genere passe de `13` `ensures` a `6`;
  - les resumes kernel visibles deviennent compacts:
    - `Kernel propagation summary`
    - `Kernel safety`
  - le nombre de goals descend de `391` a `181`;
  - le cas n'est toutefois pas encore vert a `5s`:
    - il reste un echec solver sur un `step'vc` relie au resume
      `Track -> Track`.

- Effet mesure sur la correction:
  - `tests/quarantine/non_discriminant_bad_code/require_delay_bool__bad_code.kairos`
    reste non vert apres cette passe;
  - le correctif de correction n'a donc pas ete reperdu.

- Reverifications utiles:
  - `tests/without_calls/ok/inputs/gated_echo_bundle.kairos` retombe sur
    `[]` a `5s`;
  - `tests/without_calls/ok/inputs/sticky_bypass_echo.kairos` retombe sur
    `[]` a `5s`;
  - `tests/without_calls/ok/inputs/sticky_ack_plus.kairos` retombe sur `[]`
    a `5s`.

- Limite restante:
  - `armed_delay` reste le dernier bon contre-exemple de cout solver dans le
    sous-ensemble `without_calls`;
  - la suite utile n'est plus cote produit, mais cote generation locale des
    VCs Why du cas `Track -> Track`.

## 2026-03-12 10:00 CET - reverification ciblee de `armed_delay`

- Travail tente:
  - ajout d'une plomberie pour pouvoir injecter des assertions locales de
    branche issues des invariants kernel deja exiges par `step`:
    - `lib_v2/runtime/backend/why/why_core.ml`
    - `lib_v2/runtime/backend/why/why_core.mli`
    - `lib_v2/runtime/backend/emit.ml`
    - `lib_v2/runtime/backend/emit.mli`

- Observation importante:
  - sur `armed_delay`, le Why imprime ne montre pas encore d'`assert { ... }`
    explicite dans la branche `Track`;
  - en revanche, apres rebuild propre et reruns cibles isoles, le cas
    `tests/without_calls/ok/inputs/armed_delay.kairos` retombe maintenant
    stablement sur `[]` a `5s` (plusieurs replays consecutifs).

- Statut de correction reverifie:
  - `tests/quarantine/non_discriminant_bad_code/require_delay_bool__bad_code.kairos`
    continue de produire des goals en echec;
  - on n'a donc pas reintroduit de faux vert evident en obtenant ce retour au
    vert sur `armed_delay`.

- Interpretation honnête:
  - le point bloquant `armed_delay` n'est plus reproduit en replay cible a
    `5s`;
  - je n'attribue pas encore avec certitude cette amelioration a
    l'injection d'assertions locales, puisque le Why imprime ne les expose
    pas encore visiblement pour ce cas;
  - l'etape utile suivante n'est plus `armed_delay` seul, mais le rerun
    complet de `without_calls`.

## 2026-03-12 10:15 CET - campagne `without_calls` relancee

- Action:
  - relance de `scripts/validate_ok_ko.sh ... 5 without_calls`.

- Resultat pratique:
  - la campagne n'a pas ete menee jusqu'au resume final de cette relance;
  - elle a du etre interrompue apres plusieurs minutes car
    `credit_balance_monitor.kairos` restait en cours d'analyse a lui seul;
  - la contrainte `5s` par obligation etait bien respectee, mais pas de borne
    globale par fichier, donc la campagne peut rester longue malgre tout.

- Information utile extraite avant interruption:
  - dans `without_calls_ok_report.tsv.tmp`, les deux premiers cas etaient:
    - `armed_delay.kairos    FAILED    1`
    - `armed_fault_monitor.kairos    FAILED    4`
  - dans `without_calls_ko_report.tsv.tmp`, les cas deja executes etaient tous
    `INVALID`; aucun faux vert observe dans ce prefixe de campagne.

- Conclusion honnete:
  - les reverifications ciblees isolees montraient `armed_delay` vert a `5s`,
    mais la campagne sequentielle complete ne reproduit pas encore cette
    stabilite;
  - il reste donc une variabilite de performance solver en contexte de
    campagne, et `without_calls` ne peut pas encore etre declare propre.

## 2026-03-12 17:40 CET - timeout global par fichier dans le validateur

- Changement implemente:
  - `scripts/validate_ok_ko.sh` accepte maintenant un budget global
    supplementaire par fichier (`timeout_per_file`, par defaut `60s`);
  - execution encapsulee via `perl` + `alarm` pour tuer proprement un
    `cli/main.exe` trop long;
  - ajout des modes:
    - `single_ok`
    - `single_ko`
    afin de classifier un fichier unique avec exactement la meme logique que
    la campagne.

- Motivation:
  - sans borne par fichier, `credit_balance_monitor.kairos` pouvait occuper la
    campagne pendant plusieurs minutes malgre `5s` par obligation;
  - cela rendait la suite `without_calls` inexploitable comme outil de
    diagnostic iteratif.

- Verification ciblee avec le nouveau chemin:
  - `tests/without_calls/ok/inputs/armed_delay.kairos`
    - resultat: `FAILED 1`
  - `tests/without_calls/ok/inputs/armed_fault_monitor.kairos`
    - resultat: `TIMEOUT file_timeout_60s`
  - `tests/without_calls/ok/inputs/credit_balance_monitor.kairos`
    - resultat: `TIMEOUT file_timeout_60s`

- Conclusion mise a jour:
  - `armed_delay` n'est pas stabilise, meme avec le chemin campagne borne;
  - `armed_fault_monitor` et `credit_balance_monitor` ne bloquent plus la
    campagne, mais restent des cas de cout solver excessif;
  - la prochaine passe doit se concentrer sur ces trois cas avant toute
    relance complete de `without_calls`.

## 2026-03-12 18:05 CET - simplification booléenne backend Why

- Objectif:
  - reduire la masse logique envoyee a Why/Z3 sur les trois cas directeurs
    `without_calls`:
    - `armed_delay`
    - `armed_fault_monitor`
    - `credit_balance_monitor`

- Changements implementes:
  - nouveau helper:
    - `simplify_term_bool` dans
      `lib_v2/runtime/core/utils/support.ml`
      et expose dans
      `lib_v2/runtime/core/utils/support.mli`
  - cette simplification est branchee dans:
    - `lib_v2/runtime/backend/why/why_contracts.ml`
      pour les clauses kernel et la normalisation finale des `pre/post`;
    - `lib_v2/runtime/backend/emit.ml`
      pour les assertions locales de branche.

- Effet confirme sur le Why genere:
  - `armed_delay`:
    - la branche `Track` contient maintenant explicitement:
      `assert { (vars.__aut_state = Aut1) -> (vars.z = vars.__pre_k1_x) }`
    - la clause de surete `Track -> Track` est emise comme une negation simple,
      plus compacte.
  - `credit_balance_monitor`:
    - les antecedents contenant auparavant `... /\\ false` ne sont plus emis
      tels quels; on observe une simplification partielle des VCs.

- Verification finale sur le chemin de validation borne:
  - `armed_delay.kairos`
    - `FAILED 1`
  - `armed_fault_monitor.kairos`
    - `TIMEOUT file_timeout_60s`
  - `credit_balance_monitor.kairos`
    - `TIMEOUT file_timeout_60s`

- Conclusion honnete:
  - la simplification backend ameliore nettement la lisibilite du Why et
    supprime une partie de la masse vacue;
  - elle ne suffit pas encore a faire retomber les trois cas directeurs dans
    le vert;
  - le residu semble maintenant relever moins d'un oubli de simplification
    globale que de la structure meme des obligations de certains automates /
    produits.

## 2026-03-12 - Filtrage structurel des contrats helper par etat source

- Objectif:
  - rendre le decoupage `step -> step_from_<state>` reellement utile pour
    Why3, en evitant qu'un helper de source `Track` porte encore les contrats
    `Init` et `Idle`.

- Correctifs gardes:
  - `lib_v2/runtime/backend/why/why_types.ml`
  - `lib_v2/runtime/backend/why/why_types.mli`
  - `lib_v2/runtime/backend/why/why_contracts.ml`
  - `lib_v2/runtime/backend/emit.ml`

- Changements implementes:
  - ajout de metadonnees `pre_source_states` / `post_source_states` dans
    `contract_info`;
  - extraction du `prog_state` source directement depuis les hypotheses de
    clauses kernel `PreviousTick`;
  - alignement corrige entre:
    - l'ordre retourne par `build_contracts`;
    - les labels;
    - les `vcid`;
    - les tags d'etat source;
  - ajout d'une precondition structurelle `vars.st = <State>` sur chaque
    helper `step_from_<state>`.

- Effet constate sur `armed_delay`:
  - avant:
    - `step_from_track` portait encore des `ensures` issues de `Init` et
      `Idle`;
    - classification borne:
      `TIMEOUT file_timeout_60s`, puis `FAILED 3` selon les etats intermediaires.
  - apres correction du filtrage et de l'alignement:
    - `step_from_track` ne porte plus que les deux obligations `Track`;
    - `armed_delay.kairos` retombe a `FAILED 2` au lieu d'un timeout;
    - `armed_fault_monitor.kairos` reste `TIMEOUT file_timeout_60s`;
    - `credit_balance_monitor.kairos` reste `TIMEOUT file_timeout_60s`.

- Tentative rejetee:
  - ajout d'une precondition helper supplementaire deduite du produit:
    `vars.__aut_state = <Aut>` quand l'etat programme n'a qu'un seul etat
    automate possible;
  - effet mesure sur `armed_delay`:
    - regression de `FAILED 2` vers `FAILED 5`;
  - decision:
    - revert immediat;
    - conserver seulement la precondition structurelle `vars.st = <State>`.

- Diagnostic courant:
  - le timeout structurel a bien ete remplace par un noyau de VCs localise sur
    `step_from_track`;
  - la suite utile n'est plus de decouper davantage "a l'aveugle", mais
    d'inspecter la ou les obligations `step_from_track'vc` restantes
    (`FAILED 2`) et leur SMT dump.

- Tentative supplementaire 2026-03-12:
  - ajout dans `lib_v2/runtime/backend/why/why_core.ml` d'une re-injection
    des assertions de branche apres chaque affectation qui ne modifie pas les
    symboles mentionnes par l'assertion;
  - motivation:
    - faire reapparaitre explicitement, apres `y <- z`, le fait
      `(aut = Aut1) -> (z = pre)` pour aider Z3 a deduire localement
      `y = pre` dans `armed_delay`.

- Resultat:
  - build `cli` OK apres mise a jour des interfaces
    `why_core.mli` et `emit.mli`;
  - statut de `armed_delay.kairos` inchangé:
    - `FAILED 2`;
  - inspection du Why genere:
    - la reassertion attendue n'apparait pas encore dans `step_from_track`,
      donc cette instrumentation ne touche pas la forme effective du corps
      genere pour ce cas.

- Conclusion locale:
  - l'idee reste structurellement correcte, mais l'accroche courante est trop
    haute dans le pipeline (ou les actions du bloc ne passent pas par le chemin
    ou la reassertion devrait s'inserer);
  - prochain diagnostic utile:
    - inspecter la forme exacte des `action_blocks` / `runtime_action_view`
      de `Track` dans `armed_delay` pour comprendre pourquoi la reassertion ne
      s'imprime pas.

## 2026-03-12 - Diagnostic temporalite des gardes moniteur (`armed_delay`)

- Fait cle obtenu via `--dump-product`:
  - le produit de `armed_delay` contient:
    - `(Init, A0, G0) -- arm=1 --> (Track, A0, G1) [safe]`
    - `(Track, A0, G1) -- y = __pre_k1_x --> (Track, A0, G1) [safe]`
    - `(Track, A0, G1) -- not(y = __pre_k1_x) --> (Track, A0, G2) [bad_G]`
  - le noyau du probleme n'etait donc pas un simple echec solver: la clause
    de surete dependait d'une garde moniteur sur `y`, mais cette garde etait
    compilee comme `PreviousTick`, ce qui donnait a tort `old(y = pre)`.

- Alignement Rocq verifie:
  - dans `kairos-kernel/GeneratedClauses.v` et
    `kairos-kernel/RelationalTriples.v`, `no_bad_clause` / `ctx_matches_ps`
    parlent du `TickCtx` courant du pas, donc des sorties courantes du tick;
  - il faut donc compiler les gardes moniteur comme observations mixtes du
    tick:
    - sorties courantes;
    - memoire / `pre_k` de source.

- Correctif implemente:
  - dans `lib_v2/runtime/backend/why/why_contracts.ml`:
    - ajout d'un compilateur local `compile_tick_ctx_fo`;
    - application a `step.program_guard`, `step.assume_edge.guard`,
      `step.guarantee_edge.guard` quand ces faits etaient jusque-la marques
      `PreviousTick`;
    - correction d'un sur-enveloppement en `old(...)` qui annulait l'effet.

- Effet confirme sur le Why genere:
  - la surete `Track` n'est plus emise comme
    `old(not (y = __pre_k1_x))`;
  - elle devient:
    `not ((old(st = Track) /\ old(aut = Aut1)) /\ not (y = old(__pre_k1_x)))`
  - ce qui est conforme a la lecture "sortie courante / pre-histoire source".

- Effet mesure:
  - `armed_delay.kairos` passe de `FAILED 2` a `FAILED 1` dans
    `single_ok`;
  - le replay direct
    `--dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 10 --timeout-s 5`
    retourne maintenant `[]`, ce qui indique un residu d'incoherence entre:
    - le chemin `single_ok` du validateur;
    - et le replay direct CLI.

- Conclusion honnete:
  - le verrou principal de correction sur `armed_delay` etait bien un probleme
    d'encodage temporel des gardes moniteur, pas un manque de force de Why3;
  - il reste un point d'orchestration / reproductibilite a eclaircir avant de
    declarer `armed_delay` vraiment vert.

- Mise en conformite `AGENTS.md` dans la foulee:
  - le premier correctif avait ete branche directement dans
    `lib_v2/runtime/backend/why/why_contracts.ml` via un traitement special
    des gardes de pas;
  - ce point a ete remonte dans l'IR avec un nouveau temps de clause
    `StepTickContext` dans:
    - `lib_v2/runtime/middle_end/product/product_kernel_ir.ml`
    - `lib_v2/runtime/middle_end/product/product_kernel_ir.mli`
  - l'emetteur Why ne fait plus qu'implementer cette temporalite explicite,
    au lieu de deduire localement un cas special a partir des gardes
    d'automate.

- Effet confirme apres cette remontee dans l'IR:
  - le Why genere pour `armed_delay` reste semantiquement corrige:
    `vars.y = old(vars.__pre_k1_x)` au lieu de `old(vars.y = vars.__pre_k1_x)`;
  - `armed_delay.kairos` reste a `FAILED 1` en `single_ok`;
  - on preserve donc le gain de correction tout en respectant mieux la regle
    du depot: temporalite explicite dans l'IR, pas bricolage cache dans Why.

## 2026-03-12 - Ajout d'un `AGENTS.md` de depot

- Fichier ajoute:
  - [AGENTS.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/AGENTS.md)

- Motivation:
  - verrouiller explicitement une contrainte d'architecture qui etait jusqu'ici
    seulement implicite dans les echanges;
  - eviter de retomber, dans les prochaines passes backend, sur une preuve des
    faits de tick courant / variables decalees via des gardes de moniteur.

- Regle gravee dans le depot:
  - `__aut_state` est une vraie variable d'etat Kairos, et son usage reste
    autorise;
  - en revanche, les faits temporels sur:
    - tick courant,
    - `prev`,
    - `pre_k`,
    - relations source/cible,
    ne doivent pas etre reconstitues dans Why3 par reexecution des gardes
    d'automate / moniteur;
  - ces faits doivent etre exprimes directement comme relations logiques sur
    variables Kairos et variables decalees.

- Effet attendu:
  - rendre cette contrainte systematique pour les prochaines modifications;
  - servir de garde-fou avant tout changement dans:
    - `lib_v2/runtime/backend/why/`
    - `lib_v2/runtime/middle_end/product/`
    - les resumes modulaires de `call`.

- Enrichissement du fichier dans la meme passe:
  - ajout de regles compactes supplementaires sur:
    - l'appartenance des faits semantiques a l'IR / clauses kernel plutot
      qu'au backend Why;
    - l'explicitation obligatoire du temps (`courant`, `source`, `cible`,
      `pre_k`);
    - la discipline de validation quand le replay direct et le validateur ne
      sont pas d'accord;
    - la discipline sur les `bad_code`;
    - la preuve modulaire obligatoire via `.kobj`;
    - la necessite d'un mini-diagnostic avant/apres pour les changements
      backend / produit.
## 2026-03-12 - Conformite AGENTS sur les projections moniteur

### Objectif
- remettre le pipeline de preuve en conformite avec `AGENTS.md` :
  - `__aut_state` reste une vraie variable d'etat Kairos ;
  - les faits de tick courant et de decalage ne doivent plus etre reconstruits via les gardes du moniteur.

### Changement
- suppression, dans `lib_v2/runtime/middle_end/instrumentation/instrumentation.ml`, de l'injection active :
  - `Product_contracts.add_assumption_projection_requires`
  - `Product_contracts.add_bad_guarantee_projection_ensures`
- conservation de :
  - la simulation de `__aut_state`,
  - les contraintes de compatibilite moniteur/programme,
  - les invariants d'etat.

### Motivation
- ces projections reconstruisaient des obligations de preuve a partir de `assume_guard` / `guarantee_guard`, ce qui viole la regle d'architecture documentee dans `AGENTS.md`.
- les faits temporels doivent venir des clauses kernel explicites et de l'IR, pas d'une reinterpretation des gardes du moniteur dans Why.

### Etat
- changement de pipeline effectue ;
- build `bin/cli/main.exe` repasse ;
- replay direct `armed_delay` (`--dump-proof-traces-json ... --timeout-s 5`) retourne `[]` ;
- `scripts/validate_ok_ko.sh ... single_ok ... armed_delay.kairos` reste a `FAILED 1`.

### Conclusion intermediaire
- la mise en conformite `AGENTS.md` est effective sur le pipeline actif ;
- la divergence restante sur `armed_delay` n'est plus un effet des projections de gardes moniteur ;
- le prochain diagnostic doit viser l'orchestration du validateur / le chemin CLI exact qu'il utilise.

### Verification de regression ciblee
- `single_ok` apres ce changement :
  - `armed_delay.kairos` -> `FAILED 1`
  - `gated_echo_bundle.kairos` -> `FAILED 4`
  - `sticky_ack_plus.kairos` -> `FAILED 1`
  - `sticky_bypass_echo.kairos` -> `FAILED 4`
- `single_ko` apres ce changement :
  - `armed_delay__bad_spec.kairos` -> `TIMEOUT file_timeout_60s`
  - `armed_delay__bad_invariant.kairos` -> `TIMEOUT file_timeout_60s`
  - `armed_delay__bad_code.kairos` -> `INVALID 2`

### Lecture
- pas de regression immediate en faux vert sur l'echantillon `ko` ;
- l'instabilite `ok` dans le chemin `single_ok` reste reelle et doit etre traitee avant toute campagne large.

### Tentatives suivantes sur les faux rouges `ok`
- tentative 1 :
  - reassertion locale des postconditions filtrees a la fin de chaque `step_from_<state>` ;
  - resultat : aucun gain sur `gated_echo_bundle` / `sticky_bypass_echo`, pas de stabilisation de `armed_delay`.
- tentative 2 :
  - promotion des clauses `OriginSafety` comme preconditions source des helpers ;
  - resultat : pas d'amelioration sur les cas `Hold`, et degradation de `armed_delay` (`FAILED 2`).
- action :
  - ces deux tentatives ont ete retirees pour ne pas laisser le depot dans un etat plus mauvais.

### Tentative IR/source summary depuis le produit
- ajout d'un nouvel origin IR `OriginSourceProductSummary` dans `product_kernel_ir` pour resumer, depuis un etat produit source, la negation des cas `bad_guarantee` sortants ;
- ajout en parallele d'une lecture directe equivalente depuis `ir.product_steps` dans `why_contracts`, pour ne pas dependre d'un passage backend opaque ;
- objectif : fournir explicitement les faits courants manquants dans `Hold` sans rejouer les gardes du moniteur.

### Resultat
- build `cli` et `emit_why_debug` repasse ;
- mais les cas directeurs restent rouges en `single_ok` :
  - `gated_echo_bundle.kairos` -> `FAILED 4`
  - `sticky_bypass_echo.kairos` -> `FAILED 4`
  - `sticky_ack_plus.kairos` -> `FAILED 1`
  - `armed_delay.kairos` -> `FAILED 1`

### Lecture
- le diagnostic "il manque un fait source courant" etait partiellement juste, mais pas suffisant ;
- le verrou residuel n'est pas encore traite par un simple resume source derive du produit.

### Diagnostic de tuyauterie precise
- instrumentation temporaire de `emit.ml` et `why_contracts.ml` sur `gated_echo_bundle` :
  - `contracts.pre` ne contient qu'un seul terme, l'invariant source d'etat ;
  - `helper_pre(Hold)` ne contient que `st = Hold` et cet invariant ;
  - le resume source attendu n'arrive donc pas jusqu'aux helpers.
- l'instrumentation `why_contracts` montre :
  - le produit contient bien `Hold/Aut1 safe` et `Hold/Aut1 badG` ;
  - `src_states = 1` pour les resumes source ;
  - mais `bad_cases` retombe a `0` dans le calcul de resume source.
- hypothese de travail confirmee :
  - le cas `badG` se perd dans la reconstruction du resume source avant emission Why ;
  - la derniere tentative consistant a ne plus resimplifier ce cas n'a pas suffi a faire repasser les cas directeurs.

### Etat apres nettoyage
- instrumentation temporaire retiree ;
- build `cli` repasse ;
- resultats cibles les plus recents apres cette passe :
  - `gated_echo_bundle` -> `FAILED 4`
  - `sticky_bypass_echo` -> `FAILED 4`
  - `sticky_ack_plus` -> `TIMEOUT file_timeout_60s`
  - `armed_delay` -> `FAILED 2`

### Diagnostic courant
- les faux rouges `Hold` (`gated_echo_bundle`, `sticky_bypass_echo`) semblent manquer d'un resume/source invariant reliant la memoire locale (`hold`, `latched`) au `pre_k` correspondant ;
- ce lien ne doit pas etre reintroduit via des gardes moniteur ;
- il faut le produire proprement depuis l'IR / une relation source-etat explicite.

## Mise a jour 2026-03-12 - Resume source explicite et verrou courant

### Actions menees
- tentative de simplification locale dans `why_contracts.ml` pour normaliser `FNot disj` avant compilation Why ;
- tentative de bascule vers une source de verite plus propre :
  - produire `OriginSourceProductSummary` depuis `product_kernel_ir.ml`,
  - puis consommer directement ces clauses IR dans `why_contracts.ml` ;
- ajout temporaire d'assertions locales de branche dans `emit.ml` en reutilisant les preconditions kernel deja calculees.

### Constats confirmes
- le vrai bug local etait dans `build_source_summary_clauses` :
  - la reconstruction depuis les `bad_G` passait par une simplification qui ecrasait le resume utile ;
  - et le controle JSON fait plus tot etait trompeur parce que `@@deriving yojson` encode les variants comme listes (`["OriginSourceProductSummary"]`) et non comme chaines simples.
- apres correction :
  - `/tmp/gated_echo_bundle.kobj` contient bien une clause `OriginSourceProductSummary` ancree sur `Hold/A0/G1` ;
  - cette clause n'est plus `FactFormula FTrue`, elle porte bien la negation du cas `bad_G`.

### Effet observe
- les replays directs suivants retombent maintenant sur `0` goal en echec :
  - `gated_echo_bundle.kairos`
  - `sticky_bypass_echo.kairos`
- `armed_delay.kairos` s'ameliore mais reste rouge en replay cible (`FAILED 1` ou voisin selon le chemin).

### Nouveau verrou
- le validateur `scripts/validate_ok_ko.sh` reste divergent :
  - en replay direct CLI, `gated_echo_bundle` et `sticky_bypass_echo` donnent `0` ;
  - en `single_ok`, ils retombent encore en `TIMEOUT file_timeout_60s`.
- la reduction de `--max-proof-traces` et la suppression de `opam exec` dans le validateur n'ont pas suffi a faire disparaitre ce timeout de campagne.

### Etat laisse dans le depot
- la correction IR sur `OriginSourceProductSummary` est conservee ;
- le fallback Why depuis `product_steps` est toujours present comme filet temporaire ;
- l'instrumentation de debug a ete retiree, sauf le strict minimum deja nettoye.

## Mise a jour 2026-03-12 - Rebranchement Why sur les clauses IR

### Ce qui a ete fait
- `why_contracts.ml` a ete rebranche sur la consommation directe de `OriginSourceProductSummary` depuis `ir.generated_clauses` ;
- la consommation directe normalise maintenant localement les clauses de la forme `not (not A or not B)` en `A /\ B` avant compilation Why.

### Verification
- le Why genere pour `gated_echo_bundle` contient maintenant explicitement :
  - `[@origin:kernel_source_product_summary]`
  - avec la forme utile `y = __pre_k1_x /\ z = y`.

### Resolution locale sur `Hold`
- le residu `step_from_hold'vc` venait du fait que `emit.ml` reinjectait comme assertions locales de branche des preconditions qui ne sont pas stables apres affectation ;
- en particulier, `kernel_source_product_summary` etait reaffirme a tort apres `y <- hold` / `z <- hold`.
- correction appliquee :
  - les `branch_asserts` ne reutilisent plus les preconditions contractuelles ;
  - elles ne gardent que les vraies invariants d'etat locales.

### Resultat cible
- replay direct `gated_echo_bundle.kairos` -> `0`
- replay direct `sticky_bypass_echo.kairos` -> `0`
- `single_ok` :
  - `gated_echo_bundle.kairos` -> `OK`
  - `sticky_bypass_echo.kairos` -> `OK`
  - `sticky_ack_plus.kairos` -> `OK`
  - `armed_delay.kairos` -> `OK`

### Orchestration
- le validateur `single_ok` a ete remis sur `opam exec -- "$cli"` pour retrouver la configuration Why3 correcte ;
- le chemin sans `opam exec` pouvait perdre la configuration prover (`No prover ... "z3"`).

## Mise a jour 2026-03-12 - Hypotheses globales et filtrage moniteur residuel

### Correctifs conserves
- `why_contract_plan.ml` conserve maintenant les `transition_requires_pre` meme lorsque `use_kernel_product_contracts = true` :
  - les obligations kernel remplacent des resumes de preuve, pas les hypotheses globales d'admissibilite utilisateur ;
  - effet direct confirme sur des cas comme `require_delay_bool`, ou les hypotheses `u = 0 \/ u = 1` reapparaissent bien dans `step_from_run`.
- en mode kernel, les `requires` d'origine `Compatibility` ne sont plus reinjectes dans le backend Why via `transition_requires_pre` ;
  - cela aligne mieux le pipeline avec `AGENTS.md` : ne pas rejouer la semantique du moniteur pour parler du tick courant / des delais.
- `instrumentation.ml` ne reinjecte plus `add_monitor_compatibility_requires` dans le pipeline actif.

### Effets verifies
- `single_ok` revenus au vert apres rebuild stabilise :
  - `require_delay_bool.kairos`
  - `traffic3.kairos`
- controle `ko` maintenu :
  - `armed_delay__bad_code.kairos` reste `INVALID`.

### Tentative revertie
- tentative d'ajout d'assertions locales apres affectation non auto-referencee dans `why_core.ml` :
  - idee : exposer explicitement des faits du type `z = 0` apres `z := 0` ;
  - resultat : pas de gain sur `reset_zero_sink`, et regression sur `toggle` ;
  - decision : revert complet de cette tentative.

### Etat honnete en fin de passe
- les correctifs utiles conserves sont :
  - maintien des `transition_requires_pre` sous kernel ;
  - filtrage des `Compatibility` moniteur en mode kernel ;
  - suppression des `monitor_compatibility_requires` actifs dans l'instrumentation ;
  - separation entree/sticky deja mise en place pour les assertions de helper.
- verrous encore ouverts dans `without_calls/ok` :
  - `reset_zero_sink.kairos` reste `FAILED 1` ;
  - `toggle.kairos` est redevenu rouge a la fin de cette passe et doit etre re-isole proprement sur l'etat courant.

### Lecture technique du residu `reset_zero_sink`
- le residu n'est plus pollue par les anciennes hypotheses moniteur les plus fautives ;
- le but restant est un `step_from_zero'vc` pilote par une clause `kernel_propagation_summary` sur l'etat `Zero` ;
- les hypotheses minimales encore visibles sont des resumes source de type :
  - `Zero/Aut0 -> not ((not reset=1 /\ z=0) \/ (not y=0 /\ z=0))`
  - `Zero/Aut1 -> reset=1 /\ y=0`
- cela suggere que la forme actuelle des `OriginSourceProductSummary` pour `reset_zero_sink` reste trop faible ou trop indirecte pour fermer le cas `Zero -> Zero` a `5s`.

## Mise a jour 2026-03-12 - Diagnostic comparatif approfondi `toggle` / `reset_zero_sink`

### `toggle`
- IR observe :
  - les `product_steps` sont semantiquement simples et propres ;
  - les `OriginSourceProductSummary` exportes sont elementaires :
    - `Init/A0/G0 -> y = 0`
    - `Run/A0/G0 -> y = 0`
    - `Run/A0/G1 -> y = 1`
- lecture Why :
  - `step_from_run` porte encore un `requires` d'origine `compatibility` ;
  - il porte aussi les deux resumes source `kernel_source_product_summary` attendus.
- deduction :
  - le probleme residuel ne vient pas d'un resume source mal calcule ;
  - il vient probablement d'un reliquat de precondition `Compatibility` encore injecte ailleurs que dans `transition_requires_pre`.

### `reset_zero_sink`
- IR observe :
  - le produit explicite est beaucoup plus riche ;
  - pour `Zero`, on a des pas `safe`, `bad_guarantee` et `bad_assumption` concurrents ;
  - les `guarantee_edge.guard` des `bad_guarantee` sont de grosses disjonctions sur `reset`, `y`, `z`.
- trace Why actuelle :
  - le residu est toujours `step_from_zero'vc` ;
  - le noyau minimal ne depend plus des anciennes hypotheses moniteur les plus fortes ;
  - mais le Why genere contient encore un `requires` d'origine `compatibility` sur `step_from_zero`.
- deduction :
  - comme pour `toggle`, il reste une fuite de `Compatibility` dans la generation des helpers ;
  - en plus, meme sans cette fuite, la forme actuelle des resumes source pour `Zero` est tres indirecte et peu solver-friendly.

### Recoupement Rocq
- la formalisation Rocq (`GeneratedClauses.v`, `RelationalTriples.v`) ne genere pas de preconditions moniteur de cette forme pour prouver les pas ;
- elle raisonne sur :
  - `ctx_matches_ps`
  - `coherence_now`
  - les clauses de securite / propagation
- conclusion :
  - tout residu `origin:compatibility` dans les helpers Why du mode kernel doit etre considere comme suspect jusqu'a preuve du contraire.

## Mise a jour 2026-03-12 - Suppression effective de la fuite `Compatibility` dans les helpers

### Correctif applique
- `why_contract_plan.ml` filtre maintenant, en mode kernel :
  - les `Compatibility`,
  - et les `Coherency` qui mentionnent explicitement `__aut_state`.
- `emit.ml` filtre aussi les preconditions de helper dont le label d'origine reste `Compatibility` quand le mode kernel est actif.

### Verification directe
- `emit_why_debug` sur `toggle.kairos` :
  - `step_from_run` ne contient plus le `requires` parasite de forme
    `Run /\ Aut0 -> y = 1` ;
  - il ne garde plus que :
    - `Run /\ Aut0 -> y = 0`
    - `Run /\ Aut1 -> y = 1`
- les controles lateraux restent bons :
  - `require_delay_bool.kairos` -> `OK 0`
  - `armed_delay__bad_code.kairos` -> `INVALID 1`

### Resultat honnete
- malgre cette suppression effective de la fuite `Compatibility` :
  - `toggle.kairos` reste `FAILED 1`
  - `reset_zero_sink.kairos` reste `FAILED 1`

### Deduction
- le prochain verrou n'est plus la provenance moniteur ;
- on a maintenant isole des residus qui sont bien des residus kernel / solver sur les resumes source et/ou la structuration locale des VCs.

## Mise a jour 2026-03-13 - Synthese documentaire IR et cas file `delay_int`

### But
- produire une documentation stable de ce qui est genere au niveau IR pour la preuve ;
- expliciter la forme et le role des obligations ;
- illustrer chaque niveau sur un exemple minimal.

### Cas retenu
- `tests/ok/inputs/delay_int.kairos`

### Niveau observes
1. source Kairos ;
2. produit explicite (`--dump-product`) ;
3. OBC instrumente (`--dump-obc`) ;
4. objet compile `.kobj` (`--emit-kobj`) ;
5. Why genere (`--dump-why`).

### Points documentes
- familles d'obligations `generated_clauses` :
  - `OriginInitNodeInvariant`
  - `OriginInitAutomatonCoherence`
  - `OriginSourceProductSummary`
  - `OriginPropagationNodeInvariant`
  - `OriginPropagationAutomatonCoherence`
  - `OriginSafety`
- familles d'obligations `relational_generated_clauses` ;
- temporalite :
  - `CurrentTick`
  - `PreviousTick`
  - `StepTickContext`
- abaissement de `pre(x,k)` vers `__pre_k...` ;
- structure du `tick_summary` exporte.

### Sortie produite
- `docs/ir_obligations_etude_delay_int_2026-03-13.md`
- PDF associe prevu via `pandoc` + `xelatex`.

### Observation architecturale importante
- le chemin cible de preuve est bien `relational_generated_clauses` ;
- `product_steps` et `generated_clauses` restent utiles comme niveaux de construction/traçabilite ;
- le `tick_summary` exporte conserve encore des occurrences de `HPreK`, ce qui est note comme dette d'alignement residuelle.
