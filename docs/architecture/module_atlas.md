# Atlas Des Modules Kairos

Cette page repond a la question pratique : "qui fait quoi, et dans quel
fichier ?"

Le graphe le plus utile est celui-ci :

![Kairos module flow](manual/module-flow.svg)

Il ne montre pas toutes les dependances. Il montre le chemin que suit une
commande Kairos normale.

## Lecture Rapide

```text
bin/cli/kairos.ml
  -> Kairos_engine.Api
  -> Engine_flow
  -> Kairos_frontend
  -> kairos_runtime_core / Pipeline_build
  -> kairos-automata-contract
  -> kairos-spot-adapter
  -> kairos_runtime_automata / Runtime_automata_source
  -> Orchestration / From_model / passes
  -> Engine_flow / Pipeline_outputs
  -> kairos_runtime_proof ou kairos_runtime_diagnostics
```

Le serveur LSP et la CLI entrent par `Kairos_engine.Api`. Leurs données
publiques utilisent le contrat canonique `Pipeline_types`, exposé sous le nom
`Kairos_engine.Api.Contract`. Il n'existe plus de copie de ce contrat ni de
conversion vers des DTO de moteur autonomes.

La façade appartient à `kairos-engine-runtime` et délègue directement au flux
concret privé `Engine_flow`. Celui-ci coordonne le frontend et les
bibliothèques runtime spécialisées. Les paquets `kairos-lsp` et `kairos-cli`
n'importent donc ni le domaine, ni les backends, ni les modules
d'orchestration internes, sans qu'une couche application/composition
intermédiaire soit nécessaire.

La separation essentielle est :

```text
Correction:
  lib/domain/core
  lib/domain/verification
  lib/domain/proof_export

Execution de l'outil:
  lib/engine
  lib/adapters/*
  bin/*
```

## Parcours D'une Commande `--prove`

| Etape | Module / fichier | Fonction cle | Role |
| --- | --- | --- | --- |
| 1 | `bin/cli/kairos.ml` | `exec_action` | Decode les options CLI et choisit l'action |
| 2 | `lib/engine/api.ml` | `run` | Façade publique ; délègue au moteur concret |
| 3 | `lib/engine/engine_flow.ml` | `run` | Coordonne directement parsing, snapshot, sorties et timing |
| 4 | `lib/adapters/in/kairos_lang/kairos_frontend.ml` | `parse_input` | Lit le fichier, parse, elabore, produit `Verification_model` |
| 5 | `lib/adapters/out/runtime/orchestration/core/pipeline_build.ml` | `prepare_program` | Prepare le programme runtime, fusionne l'IR backend et calcule une fois les projections de contrats avec leur index de formules |
| 6 | `lib/adapters/out/runtime/orchestration/core/contract_partition.ml` | `partition_program` | Regroupe ou preserve les contrats publics selon les options |
| 7 | `lib/adapters/out/runtime/orchestration/automata/runtime_automata_source.ml` | `produce_with_spot` | Produit un paquet d'automates fourni au core runtime |
| 8 | `lib/adapters/out/runtime/orchestration/automata/automata_generation.ml` | `run` | Transforme assumptions/guarantees en automates via un builder injecte |
| 9 | `packages/spot/spot_automaton_builder.ml` | `build` | Paquet autonome appelant Spot sur le contrat neutre |
| 10 | `lib/domain/verification/orchestration.ml` | `build_reference_product` | Point nomme du produit de reference, apres validation de forme des automates |
| 11 | `lib/domain/verification/from_model.ml` | `analyze_model_program` | Construit directement, pour chaque noeud, le modele, l'analyse produit et l'IR avec ses summaries |
| 12 | `lib/domain/verification/orchestration.ml` | `build_instrumented_ir` | Enchaine les passes historiques, puis retourne directement l'IR abaisse et interne par `Temporal_lower` |
| 13 | `lib/adapters/out/runtime/orchestration/core/runtime_snapshot.ml` | `pipeline_snapshot` | Contient les ASTs/modeles, l'IR abaisse et les plans de preuve reutilises par les sorties |
| 14 | `lib/engine/pipeline_outputs.ml` | `build_outputs` | En mode `--prove`, evite les dumps lourds et lance le proof runner |
| 15 | `lib/adapters/out/runtime/orchestration/outputs/proof_runner.ml` | `run` | Soumet le WhyML et attribue les resultats neutres |
| 16 | `lib/adapters/out/provers/why3/*` | `Why_compile`, `Why_pipeline` | Projection de l'IR Kairos vers WhyML |
| 17 | `packages/why3/*` | `Why_execution`, `Why_contract_prove` | Paquet autonome encapsulant tous les types et appels Why3/provers |

Point important : en mode `--prove` minimal, `Pipeline_outputs.is_prove_only_run`
fait que `Pipeline_artifact_bundle.build` n'est pas appele. Donc les graphes
et gros dumps ne sont pas produits.

## Parcours D'un Dump De Diagnostic

| Etape | Module / fichier | Fonction cle | Role |
| --- | --- | --- | --- |
| 1 | `bin/cli/kairos.ml` | `exec_dump_mode` | Choisit le dump demande |
| 2 | `lib/engine/api.ml`, `lib/engine/engine_flow.ml` | passe de dump demandee | Construit le snapshot et choisit la projection sans use-case intermediaire |
| 3 | `lib/adapters/out/runtime/orchestration/outputs/pipeline_artifact_bundle.ml` | `build` | Construit graphes, textes et donnees proof-kernel |
| 4 | `lib/domain/proof_export/proof_kernel_pass.ml` | `compile_node` | Produit `Proof_kernel_types.node_ir` |
| 5 | `lib/engine/output_mapper.ml` | `map_outputs` | Assemble les sorties canoniques |

Ce chemin est fait pour inspection. Il n'est pas lance par defaut dans
`--prove`.

## Donnees Principales

| Donnee | Type / module | Cree par | Consomme par |
| --- | --- | --- | --- |
| Contrat canonique du moteur | `Kairos_engine.Api.Contract` alias de `Pipeline_types` | moteur concret et services runtime | CLI, LSP, clients embarqués |
| Surface AST | `Kx_surface_syntax` | Parser/frontend | `Kx_elaborate` |
| Elaborated AST | `Kx_ast` | `Kx_parse_api` / `Kx_elaborate` | `Kairos_to_model` |
| Core program model | `Verification_model.program_model` | `Kairos_to_model` | `Pipeline_build`, runtime automata source, `From_model` |
| Automata tool request/response | `Automata_exchange.request/response` | `kairos_runtime_automata` / Spot | Spot adapter / runtime conversion |
| Runtime model | `Verification_model.program_model` | `Contract_partition` | Automata/product |
| Automata | `Automaton_types.automata_spec` | `kairos_runtime_automata` + Spot adapter | `From_model`, graph renderers |
| Product summaries | `Ir.node_ir list` | `From_model.analyze_model_program` | `Pre/Post/...`, renderers |
| IR historique transitoire | `Ir.node_ir list` | `Orchestration.build_instrumented_ir` apres `Post` | `Temporal_lower` uniquement, valeur non retenue |
| Lowered backend IR | `Ir.program_ir` | `Orchestration.build_instrumented_ir` apres `Temporal_lower` | `Pipeline_build`, diagnostics et planification de preuve |
| Plan de preuve | `Proof_plan.t` | `lib/domain/verification`, construit une fois par `Pipeline_build` depuis les contrats de pas | compilateur Why3, attribution des buts |
| Runtime snapshot | `Runtime_snapshot.pipeline_snapshot` | `Pipeline_build` dans `kairos_runtime_core` | `Engine_flow`, proof runner, diagnostics |
| Kernel IR | `Proof_kernel_types.node_ir` | `Proof_kernel_pass` | diagnostics, projection Rocq possible apres adequation, cost report |
| Why3 AST/text | backend-specific | `Why_compile` | Contrat de preuve |
| Proof backend request | `Proof_backend_contract.request` | `Why_pipeline` | `kairos-why3-adapter` |

## Modules Par Responsabilite

### Frontend

| Module | Responsabilite |
| --- | --- |
| `kx_lexer.ml`, `kx_parser.mly` | Lexer/parser du langage Kairos |
| `kx_surface_syntax.ml` | AST de surface, avec sucre syntaxique |
| `kx_ast.ml` | AST elabore plus proche du core |
| `kx_elaborate.ml` | Orchestration de l'elaboration vers l'AST elabore |
| `kx_elaborate_names.ml` | Conventions de nommage pour indices et historiques generes |
| `kx_elaborate_env.ml` | Environnement d'elaboration et expansion des declarations indexees |
| `kx_elaborate_subst.ml` | Substitution capture-avoiding sur la syntaxe de surface |
| `kx_elaborate_logic.ml` | Abaissement des expressions, predicates et formules LTL de surface |
| `kx_elaborate_histories.ml` | Generation des ghosts et transitions pour historiques de surface |
| `kx_elaborate_observers.ml` | Generation des declarations et updates proof-only des observers |
| `kx_elaborate_state_selectors.ml` | Expansion des selecteurs d'etats pour invariants de surface |
| `kx_elaborate_validation.ml` | Validations de surface avant abaissement vers l'AST elabore |
| `kx_parse_api.ml` | API de parsing utilisee par CLI/LSP/tests |
| `kairos_to_model_validation_common.ml` | Primitives partagees de validation semantique du modele |
| `kairos_to_model_function_validation.ml` | Validation des declarations de fonctions pures Kairos |
| `kairos_to_model_node_validation.ml` | Validation des noeuds `Verification_model` elabores |
| `kairos_to_model_validation.ml` | Facade de validation semantique du `Verification_model` elabore |
| `kairos_to_model.ml` | Conversion Kx AST vers `Verification_model` |
| `kairos_frontend.ml` | Adaptateur frontend complet : fichier -> `Kairos_frontend.input` |

### Moteur Concret Et Contrat

| Module | Responsabilite |
| --- | --- |
| `pipeline_types.ml/mli` | Contrat canonique de configuration, options, sorties, traces et erreurs ; exposé par `Kairos_engine.Api.Contract` |
| `lib/engine/api.ml/mli` | Façade publique en processus consommée par les adaptateurs de livraison |
| `lib/engine/engine_flow.ml` | Orchestration concrète unique : frontend, snapshot, sorties, callbacks et timing |
| `lib/engine/pipeline_outputs.ml` | Sélection entre preuve minimale et sorties avec artefacts |
| `lib/engine/output_mapper.ml` | Assemblage des sorties canoniques du moteur |
| `lib/engine/engine_timing_fields.ml` | Champs de metriques pour les metadonnees de timing |
| `lib/engine/engine_vc_taxonomy.ml` | Agrégation de taxonomie VC pour les metadonnees de timing |
| `lib/engine/engine_timing_meta.ml` | Assemblage des metadonnees de timing du moteur |
| `Kairos_engine.Graphviz_render` | Service public du moteur pour invoquer Graphviz sur du texte DOT |

### Contrats Des Outils Externes

| Module | Responsabilite |
| --- | --- |
| `tool_protocol.ml/mli` | Version commune et rejet explicite des protocoles incompatibles |
| `proof_backend_contract.ml/mli` | IR canonique et politique d'optimisation remis explicitement au backend de preuve |
| `packages/automata-contract/automata_exchange.ml/mli` | Contrat LTL/automates autonome, serialisable et fonde uniquement sur des noms d'atomes opaques |
| `automata_exchange_adapter.ml/mli` | Conversions Kairos vers le contrat neutre et retour vers `Automaton_types` |
| `packages/spot/*` | Adaptateur Spot emballable et testable independamment, sans dependance interne a Kairos |

### Noyau De Correction

| Module | Responsabilite |
| --- | --- |
| `core_syntax.ml` | Expressions, formules, statements, types de base |
| `verification_model.ml` | Modele core du programme Kairos |
| `ir.ml/mli` | IR de summaries produit x automates, indexe par phase historique ou sans historique |
| `pre_k_layout.ml`, `pre_k_lowering.ml` | Representation explicite de l'historique temporel |
| `product_build.ml` | Exploration du produit programme x automates |
| `from_model.ml` | Conversion modele + automates -> summaries |
| `fo_current_input.ml` | Predicat `no_current_input` pour les faits end-of-instant |
| `pre.ml` | Ajoute les hypotheses de pas |
| `product_reachability.ml` | Ajoute les obligations liees aux destinations inatteignables |
| `post.ml` | Ajoute les obligations de sortie/progression |
| `formula_canonical.ml` | Cle structurelle et internement generiques des formules |
| `contract_formula_index.ml` | Construit les classes par égalité structurelle puis résout les occurrences indexées par `oid` |
| `temporal_lower.ml` | Frontière typée : abaisse l'IR historique (`pre/pre_k`) et interne les résultats sans localisation |
| `kernel_clause_projection.ml/mli` | Projection neutre des `KernelClause` Rocq et clauses classifiees |
| `orchestration.ml` | Ordre des passes et point `build_reference_product` |

### Export Proof-Kernel / Rocq Futur

| Module | Responsabilite |
| --- | --- |
| `proof_kernel_types.ml/mli` | Format d'echange proof-kernel |
| `proof_kernel_product.ml` | Produit explicite exporte |
| `proof_kernel_product_lookup.ml` | Appariement entre pas produit exportes et summaries canoniques |
| `proof_kernel_clause_context.ml/mli` | Bridge de contexte produit IR vers `Kernel_clause_projection` |
| `proof_kernel_generated_clauses.ml` | Adaptateur depuis `Kernel_clause_projection` avant lowering relationnel |
| `proof_kernel_clause_lowering.ml` | Clauses relationnelles |
| `proof_kernel_step_summaries.ml` | Groupes de pas proof-kernel |
| `proof_kernel_pass.ml` | Compilation d'un noeud vers `Proof_kernel_types.node_ir` |

### Runtime Et Sorties

| Bibliotheque / module | Responsabilite |
| --- | --- |
| `kairos_runtime_core` | Construction du snapshot, merge runtime/source, instrumentation info |
| `pipeline_build.ml` | Construction du snapshot complet |
| `runtime_snapshot.ml` | Type du snapshot |
| `instrumentation_info_builder.ml` | Informations supplementaires pour l'inspection |
| `kairos_runtime_automata` | Production externe des automates fournis au core runtime |
| `runtime_automata_source.ml` | Appel direct du paquet Spot et enregistrement du timing |
| `automata_exchange_adapter.ml` | Conversion entre formules Kairos et contrat d'automates neutre |
| `kairos_runtime_proof` | Execution Why3/provers, attribution des buts, evenements de preuve |
| `proof_goal_attribution.ml` | Attribution des buts Why3 aux pas produit et metadonnees de preuve |
| `proof_goal_results.ml` | Construction des resultats de preuve depuis les evenements Why3 |
| `proof_progress_output.ml` | Sortie CSV de progression des preuves |
| `proof_text_blocks.ml` | Assemblage des dumps texte avec spans |
| `proof_trace_diagnostics.ml` | Diagnostics attaches aux traces de preuve |
| `proof_traces.ml` | Construction des traces de preuve publiques |
| `proof_runner.ml` | Orchestre la projection Why3, les taches et les sorties de preuve |
| `kairos_runtime_diagnostics` | Diagnostics, graphes, proof-export, rapports de cout |
| `pipeline_artifact_bundle_text.ml` | Rendus texte du bundle d'artefacts |
| `pipeline_artifact_bundle.ml` | Construit graphes, textes d'inspection et donnees proof-kernel |
| `pipeline_cost_report_common.ml` | Primitives JSON, collections et statistiques du rapport de cout |
| `pipeline_cost_report_syntax.ml` | Metriques syntaxiques du rapport de cout |
| `pipeline_cost_report_labels.ml` | Labels stables pour origines, phases et etats produit |
| `pipeline_cost_report_source.ml` | Section source du rapport de cout |
| `pipeline_cost_report_kernel.ml` | Sections proof-kernel et summaries canoniques du rapport de cout |
| `pipeline_cost_report_why3.ml` | Section texte Why3 du rapport de cout |
| `pipeline_cost_report_transition_lemmas.ml` | Analyse diagnostique des candidats de lemmes de transition |
| `pipeline_cost_report_facts.ml` | Population de formules et repetitions dans le rapport de cout |
| `pipeline_cost_report.ml` | Composition du rapport de cout du pipeline |

La façade et les sorties ne constituent plus des bibliothèques runtime
supplémentaires : `Engine_flow`, `Pipeline_outputs` et `Output_mapper`
appartiennent directement à `lib/engine`.

### Sorties Diagnostic Et Graphes

| Module | Responsabilite |
| --- | --- |
| `automata_graph_dot.ml` | Primitives neutres d'emission DOT/HTML |
| `automata_graph_format.ml` | Formatage partage des formules et labels de graphes |
| `automata_graph_contract.ml` | Rendu des automates assume/guarantee |
| `automata_graph_product.ml` | Rendu du produit programme/assume/guarantee |
| `automata_graph_program.ml` | Rendu de l'automate de controle programme |
| `automata_graph_render.ml` | Facade publique des rendus d'automates |
| `Kairos_engine.Graphviz_render` | Appel de Graphviz sur du texte DOT, possédé par le moteur concret |

### Backend Why3 Et Outils Externes

Le backend Why3 interne est consolide en 13 modules, soit 26 fichiers
`.ml`/`.mli`. La planification n'en fait plus partie : `proof_plan.ml`, dans le
domaine de verification, fixe une seule fois le groupage, la factorisation, le
partage et la provenance pour tous les backends.

| Module | Responsabilite |
| --- | --- |
| `why_product_step_names.ml` | Nommage stable des helpers Why3 par pas produit |
| `why_compile_expr.ml` | Constructeurs `Ptree`, mapping des types et operateurs, environnement et compilation des expressions |
| `why_compile_ptree_helpers.ml` | Construction de termes/specs et conversion des binders Why3 |
| `why_compile_logic.ml` | Declarations logiques et compilation des fonctions pures |
| `why_compile_formula_sharing.ml` | Emission WhyML de l'index de formules partagees choisi par le domaine |
| `why_compile_bundles.ml` | Emission des preconditions nommees et postconditions partagees deja planifiees |
| `why_compile_product_specs.ml` | Traduction directe des conditions planifiees en specifications Why3 |
| `why_compile_product_helpers.ml` | Type d'un helper, contexte, corps et emission des helpers individuels/groupes |
| `why_compile_node_common.ml` | Types, binders d'entrees/historiques et getters communs d'un noeud Why3 |
| `why_compile_modules.ml` | Assemblage final des declarations et helper units en modules Why3 |
| `why_compile_step.ml` | Compilation imperative directe de `Ir.transition` et `Core_syntax.stmt` |
| `why_compile.ml` | Facade publique et orchestration de la compilation Why3 d'un noeud |
| `why_pipeline.ml` | Impression native de l'AST et generation VC/SMT textuelle |
| `why_contract_unix_io.ml` | Helpers Unix/IPC du proof runner Why3 |
| `why_contract_proof_types.ml` | Types de résultats, événements et timings de preuve Why3 |
| `why_contract_smt_utils.ml` | Statuts, empreintes et dumps SMT-LIB |
| `why_contract_persistent_z3.ml` | Session Z3 persistante pour buffers SMT-LIB |
| `why_contract_prover_call.ml` | Préparation, impression, lancement et fallback d'un appel prouveur |
| `why_contract_workers.ml` | Distribution, IPC et cycle de vie des workers de preuve Why3 |
| `why_contract_prove.ml` | Interaction Why3/provers |
| `packages/spot/spot_automaton_builder.ml` | Adaptateur Spot autonome |
| `external_timing_types.ml` | Types des snapshots et compteurs de timing |
| `external_timing_store.ml` | Etat mutable process-local des mesures de couts |
| `external_timing.ml` | Facade publique des mesures de couts |

## Questions Pratiques

| Question | Fichier a ouvrir |
| --- | --- |
| Pourquoi `--prove` produit ou non des dumps ? | `pipeline_outputs.ml` |
| Ou sont construites les automates ? | `runtime_automata_source.ml`, puis `automata_generation.ml` et `spot_automaton_builder.ml` |
| Ou commence le kernel de reference ? | `orchestration.ml`, fonction `build_reference_product` |
| Ou sont ajoutees les hypotheses de pas ? | `pre.ml` |
| Ou sont ajoutees les obligations de sortie ? | `post.ml` |
| Ou est gere `pre/pre_k` ? | `temporal_lower.ml`, `pre_k_layout.ml`, `pre_k_lowering.ml` |
| Ou est produit le format Rocq ? | `proof_kernel_pass.ml`, `proof_kernel_types.mli` |
| Ou sont les optimisations Why3 ? | Voir la section "Backend Why3 Et Outils Externes" ci-dessus |
| Ou sont les options CLI ? | `bin/cli/kairos.ml`, `pipeline_types.ml` |

## Regle De Maintenance

Quand un module grossit ou change de role, il faut mettre cette page a jour.
Elle doit rester plus importante que les graphes automatiques pour comprendre
le code au quotidien.
