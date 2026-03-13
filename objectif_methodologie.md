# Objectif et methodologie

## Objectif courant (mise a jour 2026-03-13 - documentation visuelle IR)
Rendre la documentation IR suffisamment explicite pour servir de base de
travail fiable pour la refonte relationnelle de la preuve:
- expliquer la forme exacte des obligations a chaque niveau;
- montrer visuellement ce qui est produit par chaque etape;
- documenter sur un cas minimal (`delay_int`) la chaine complete:
  - source;
  - programme reactive instrumente;
  - produit explicite;
  - `generated_clauses`;
  - `relational_generated_clauses`;
  - emission Why.

Livrables vises:
- document Markdown detaille dans `docs/`;
- PDF regenere;
- figures explicites pour:
  - pipeline;
  - automates/produit;
  - relation transitions -> clauses;
  - temporalite de `pre_k`.

## Methodologie (mise a jour 2026-03-13 - documentation visuelle IR)
1. Partir d'un cas minimal mais non trivial:
   - `delay_int`.
2. Reutiliser les artefacts reels extraits du pipeline:
   - produit explicite;
   - OBC;
   - `.kobj`;
   - Why genere.
3. Distinguer a chaque fois:
   - ce qui est artefact de construction;
   - ce qui est deja une obligation de preuve utile;
   - ce qui est encore une dette d'architecture.
4. Preferer des figures derivant directement des artefacts reels:
   - DOT/Graphviz pour les vues structurelles;
   - tableaux explicites pour les correspondances
     transition -> clauses -> role.
5. Garder cette documentation alignee avec l'orientation architecturale retenue:
   - preuve relationnelle;
   - abaissement explicite des `pre_k` avant Why;
   - pas de monitoring execute comme support principal de preuve.
6. Ajouter une couche pedagogique explicite:
   - legende des objets manipules;
   - typologie stable des obligations;
   - anti-confusions;
   - reduction produit -> clause brute -> clause relationnelle -> Why.

## Objectif courant (mise a jour 2026-03-12 - retrait du monitoring execute)
Faire converger Kairos vers un pipeline de preuve sans monitoring execute de
la specification:
- pas de `__aut_state` comme etat de programme ou support principal de preuve;
- pas de structuration des obligations par etats `Aut*`;
- produit/automates utilises uniquement pour deriver des clauses
  relationnelles backend-agnostic;
- backend Why reduit au role de compilateur de ces clauses relationnelles.

Livrables vises:
- `AGENTS.md` corrige avec cette contrainte explicite;
- branche actuelle documentee comme branche de transition;
- plan de retrait de `__aut_state` / `Aut*` du pipeline actif;
- cas pilote minimal reconstruit sans etat moniteur;
- criteres d'extension vers `without_calls`, puis `with_calls`.

## Methodologie (mise a jour 2026-03-12 - retrait du monitoring execute)
1. Geler l'architecture courante comme etat transitoire:
   - ne plus raffiner localement les VCs qui restent encore structurees par
     `Aut*`;
   - conserver seulement les pieces backend-agnostic reutilisables.
2. Faire un inventaire explicite des dependances residuelles a
   `__aut_state` / `Aut*` dans:
   - IR produit,
   - clauses generees,
   - emission Why,
   - resumes modulaires.
3. Definir une IR cible purement relationnelle pour la preuve:
   - preconditions locales du tick,
   - relation source/cible,
   - faits exportables sur sorties et memoires,
   - resumes d'appel modulaires,
   sans etat moniteur execute.
4. Repartir d'un cas pilote minimal:
   - `tests/without_calls/ok/inputs/toggle.kairos`
   - avec reconstruction complete de son encodage sans `Aut*`.
5. Etendre ensuite progressivement:
   - reste de `without_calls`,
   - puis `with_calls`,
   - puis revalidation complete `ok/ko`.

## Etat courant (mise a jour 2026-03-12 - branche de transition)
- La branche `codex/spot-automata-migration` doit maintenant etre consideree
  comme une branche de transition.
- Elle contient des progres reutilisables:
  - `.kobj`,
  - `import`,
  - separation `with_calls` / `without_calls`,
  - resumes `OriginSourceProductSummary`,
  - nettoyage partiel du backend Why;
- mais elle ne constitue pas encore l'architecture cible tant que des preuves
  restent structurees autour de `__aut_state` / `Aut*`.
- Les prochains travaux ne doivent donc plus viser a "raffiner" cette forme,
  mais a organiser son depassement vers une preuve relationnelle pure.

## Etat courant (mise a jour 2026-03-12 - abaissement `pre_k` avant Why)
- Fait:
  - le pipeline exporte maintenant une partie des faits de preuve avec les
    `pre_k` deja abaisses en variables symboliques explicites `__pre_k...`,
    avant traduction Why;
  - cela vaut deja pour:
    - les clauses kernel exportees;
    - les resumes de tick exportes;
  - une premiere IR de preuve relationnelle existe maintenant:
    - `relational_generated_clauses`.
- Consequence:
  - Why ne doit plus etre le premier endroit qui "interprete" `pre(x,k)` sur
    ces chemins;
  - le prochain basculement consiste a faire de cette IR relationnelle
    l'entree principale du backend de preuve.
- Cas pilote retenu:
  - `tests/without_calls/ok/inputs/toggle.kairos`
- Documents de cadrage:
  - `docs/architecture_transition_inventory_2026-03-12.md`
  - `docs/relational_proof_pilot_toggle_2026-03-12.md`

## Etat courant (mise a jour 2026-03-12 - bascule active sur l'IR relationnelle)
- Fait:
  - le backend Why consomme maintenant le chemin
    `relational_generated_clauses` sur le noyau kernel actif;
  - les invariants de programme sont reintroduits seulement sous forme
    relationnelle indexee par l'etat du programme, sans `Aut*`;
  - `toggle`, `require_delay_bool`, `armed_delay` et `armed_fault_monitor`
    passent dans ce modele;
  - `armed_delay__bad_code` reste `INVALID`.
- Blocage restant:
  - `credit_balance_monitor` reste rouge a `5s`;
  - une simplification relationnelle trop agressive a ete essayee puis retiree
    car elle cassait la correction (`armed_delay__bad_code` devenait vert).
- Consequence methodologique:
  - ne pas reintroduire de simplification logique agressive non justifiee;
  - traiter `credit_balance_monitor` comme cas directeur final de
    `without_calls/ok` avant relance complete des suites.

## Objectif courant (mise a jour 2026-03-12 - rapport detaille d'architecture)
Produire un rapport PDF tres detaille sur l'architecture du programme et sur
les details d'implementation du depot `kairos-dev`, fonde sur le code reel
inspecte et non sur une description hypothetique.

Livrables vises:
- un document source en Markdown dans `docs/`;
- un PDF genere a partir de ce document;
- une analyse structuree couvrant:
  - points d'entree,
  - pipeline,
  - middle-end semantique,
  - backend Why3,
  - modularite `.kobj`,
  - execution de preuve,
  - diagnostics,
  - forces et dette technique visibles.

## Methodologie (mise a jour 2026-03-12 - rapport detaille d'architecture)
1. Partir des interfaces et points d'entree publics:
   - `README`,
   - notes d'architecture,
   - `pipeline.mli`,
   - executables CLI/LSP.
2. Descendre ensuite dans les modules pivots:
   - `pipeline_v2_indep`,
   - `product_build`,
   - `product_kernel_ir`,
   - backend Why3,
   - preuve Why3,
   - objets `.kobj`.
3. Faire apparaitre explicitement les frontieres architecturales:
   - semantique vs backend,
   - runtime view vs syntaxe Why,
   - artefacts compiles vs recompilation implicite.
4. Documenter honnetement les limites:
   - rapport base sur l'inspection du code,
   - sans pretendre a une validation formelle exhaustive.
5. Generer ensuite un PDF partageable depuis la version Markdown source.

## Objectif courant (mise a jour 2026-03-11 - modularite reelle des `call`)
Mettre en place une compilation modulaire reelle des `call`, avec:
- objets compiles `.kobj` reutilisables;
- syntaxe source `import`;
- resolution explicite des callees par objets importes;
- preuve locale du caller sur resume compile, sans recompilation implicite du
  callee.

Livrables vises:
- format objet stable et documente;
- pipeline de compilation separe:
  - parsing,
  - chargement/import,
  - normalisation/analyse,
  - IR produit,
  - backend agnostique,
  - Why/prove;
- campagne `ok/ko` integralement revalidee dans le nouveau modele.

## Methodologie (mise a jour 2026-03-11 - modularite reelle des `call`)
1. Stabiliser d'abord l'ABI modulaire:
   - signature exportee,
   - etat persistant exporte,
   - resume de tick,
   - invariants exportables.
2. Faire ensuite transiter ces objets par tout le pipeline:
   - parser `import`,
   - resolveur d'objets,
   - middle-end,
   - backend.
3. N'autoriser au site d'appel que des hypotheses provenant du resume compile.
4. Refuser toute solution ad hoc specifique a Why3 si elle court-circuite le
   modele modulaire.
5. Valider progressivement:
   - build CLI/LSP/IDE;
   - cas minimaux `call` importes;
   - campagne `ok`;
   - campagne `ko`.

## Etat courant (mise a jour 2026-03-11 - modularite reelle des `call`)
- Fait:
  - format `.kobj` introduit;
  - syntaxe `import` introduite;
  - objets importes charges explicitement dans le pipeline;
  - propagation des resumes importes jusqu'au backend;
  - exemples multi-noeuds separes en fichiers distincts avec imports explicites;
  - emission Why des appels rebranchee sur un `any` local contraint par le
    resume, au lieu d'un faux `step` importe.
- Blocage critique restant:
  - Why3 refuse encore la representation actuelle des acces a l'etat/sorties
    du callee importe dans les termes/programmes generes;
  - plusieurs tentatives ont ete essayees:
    - projections directes sur record importe,
    - getters programmes,
    - getters logiques;
  - aucune n'est encore stable sur le type-checking Why.
- Consequence:
  - la modularite structurelle est en grande partie implantee;
  - la preuve modulaire importee n'est pas encore assez stable pour lancer une
    revalidation complete `ok/ko`.

## Objectif courant (mise a jour 2026-03-11 - reduction du vieux chemin Why)
Continuer l'elimination de l'OBC annote comme pivot semantique, en retirant
progressivement de `why_contracts.ml` les blocs historiques encore presents sur
le chemin `kernel-first`, sans regression sur les cas `ok`.

Livrables vises pour cette sous-iteration:
- calcul unique et explicite des obligations de transition historiques;
- aucune evaluation de ces blocs sur le chemin `kernel-first`;
- validation systematique sur:
  - `delay_int.kairos`,
  - `resettable_delay.kairos`,
  - `delay_int_instance.kairos`.

## Methodologie (mise a jour 2026-03-11 - reduction du vieux chemin Why)
1. Identifier d'abord les blocs deja semantiquement neutralises sur le chemin
   `kernel-first`.
2. Les factoriser pour qu'ils ne soient plus calcules du tout dans ce chemin.
3. Garder le chemin legacy strictement equivalent pour les cas non encore
   couverts par l'IR abstrait.
4. Valider chaque reduction par:
   - build sequentiel `dune build`;
   - campagne CLI des trois cas garde-fous.

## Etat courant (mise a jour 2026-03-11 - reduction du vieux chemin Why)
- Fait:
  - les blocs de transition suivants sont maintenant groupes dans un seul calcul
    et court-circuites a vide sur le chemin `kernel-first`:
    - `transition_requires_pre_terms`,
    - `transition_requires_pre`,
    - `transition_requires_post`,
    - `state_post`,
    - `state_post_terms`,
    - `state_post_terms_vcid`,
    - `transition_post_to_pre`;
  - les blocs legacy suivants sont eux aussi regroupes et court-circuites sur
    le chemin `kernel-first`:
    - `instance_invariants`,
    - `instance_input_links_pre`,
    - `instance_input_links_post`,
    - `instance_delay_links_inv`,
    - `output_links`,
    - `first_step_links`,
    - `first_step_init_link_pre`,
    - `link_invariants`;
  - dans ce bloc, seul `instance_delay_links_inv` reste alimente sur le chemin
    `kernel-first`, mais depuis l'IR abstrait;
  - le contexte de labels diagnostiques a maintenant un mode `kernel_first`
    explicite; dans ce mode, seules les familles encore pertinentes sont
    construites:
    - `Transition requires`,
    - `Internal links`;
  - validation conservee sur:
    - `delay_int.kairos`,
    - `resettable_delay.kairos`,
    - `delay_int_instance.kairos`.
- Prochaine cible:
  - migrer maintenant le runtime Why lui-meme vers une vue derivee du nouvel IR
    abstrait, au lieu de `Ast.node` annote.

## Etat courant (mise a jour 2026-03-11 - dependances restantes a l'OBC annote)
- Fait:
  - audit cible des dependances restantes documente dans
    [ARCHITECTURE_REMAINING_OBC_DEPENDENCIES.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/ARCHITECTURE_REMAINING_OBC_DEPENDENCIES.md)
  - clarification de la frontiere d'architecture documentee dans
    [ARCHITECTURE_WHY_RUNTIME_VIEW.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/ARCHITECTURE_WHY_RUNTIME_VIEW.md)
- Conclusion:
  - le vrai verrou restant est concentre dans:
    - `why_env.ml`,
    - `why_core.ml`,
    - le fallback legacy de `why_contracts.ml`;
  - les couches diagnostics/labels ne sont plus le centre du probleme.
- Prochaine cible:
  - definir les types OCaml concrets de `why_runtime_view`;
  - porter `why_env.ml` sur cette vue;
  - puis porter `why_core.ml` sur cette vue.

## Etat courant (mise a jour 2026-03-11 - `why_runtime_view`)
- Fait:
  - types OCaml concrets de `why_runtime_view` introduits dans:
    - [why_runtime_view.mli](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.mli)
    - [why_runtime_view.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml)
  - `why_env.ml` consomme maintenant cette vue via `prepare_runtime_view`;
  - `prepare_node` n'est plus qu'un adaptateur.
  - `why_core.ml` compile maintenant des
    `Why_runtime_view.runtime_transition_view` au lieu de `Ast.transition`;
  - `emit.ml` branche l'execution des transitions sur
    `info.runtime_view.transitions`;
  - le shim `source_node` a ete supprime de `why_runtime_view`.
  - `why_contracts.ml` expose maintenant `build_contracts_runtime_view` et
    consomme explicitement:
    - transitions runtime,
    - instances runtime,
    - sorties runtime,
    - invariants runtime,
    au lieu de repartir principalement de `info.node`.
  - `Why_types.env_info` ne transporte plus `node : Ast.node`;
  - l'ABI active du backend Why repose maintenant sur `runtime_view`.
- Validation:
  - `delay_int.kairos`: `failed=0`
  - `resettable_delay.kairos`: `failed=0`
  - `delay_int_instance.kairos`: `failed=0`
- Prochaine cible:
  - poursuivre l'isolation du fallback legacy restant dans `why_contracts.ml`,
    en commençant par le bloc des liens/invariants d'instance;
  - viser ensuite un bloc de compatibilite minimal demonstrablement inactif sur
    les cas couverts par l'IR.

## Objectif courant (mise a jour 2026-03-11 - `instances/call` backend-agnostic)
Rendre `instances/call` compatible avec le nouvel IR abstrait sans retomber sur
l'OBC annote, en commençant par un vrai cas de test Why sur
`delay_int_instance.kairos`.

Livrables vises pour cette sous-iteration:
- Why brut inspectable sur le vrai fixture;
- site d'appel `SCall` compile sans projection fragile sur `vars.<instance>`;
- sorties mono-sortie recuperees via la valeur de retour de `step`;
- identification explicite du verrou suivant si les contrats d'instance restent
  encore sur l'ancien chemin.

## Methodologie (mise a jour 2026-03-11 - `instances/call` backend-agnostic)
1. Sortir du diagnostic a l'aveugle:
   - emettre le Why brut;
   - corriger sur le texte reel, pas sur l'erreur raccourcie.
2. Stabiliser d'abord le site d'appel runtime:
   - `let __call_inst_* = vars.<instance>`;
   - puis appel `step`;
   - puis affectation des sorties.
3. Eviter les projections de champs de callee quand une voie plus robuste
   existe:
   - pour les calls mono-sortie, utiliser la valeur de retour de `step`.
4. Valider a chaque etape par:
   - `dune build bin/cli/main.exe bin/dev/emit_why_debug.exe`,
   - inspection du Why brut,
   - execution du vrai fixture `delay_int_instance.kairos`.

## Etat courant (mise a jour 2026-03-11 - `instances/call` backend-agnostic)
- Fait:
  - utilitaire de debug `emit_why_debug`;
  - `SCall` compile maintenant avec une instance locale `__call_inst_*`;
  - pour les calls mono-sortie, le caller recupere la sortie via
    `let __call_res_* = Callee.step ...`;
  - `step` retourne bien la valeur de sortie courante cote callee.
- Verrou restant:
  - des projections d'etat d'instance restent emises dans les termes/logiques
    de contrat, avec un echec courant sur `Delay_core.__delay_core_st`.
- Consequence:
  - la lecture des sorties au site d'appel n'est plus le probleme principal;
  - la prochaine etape est de migrer les relations/contracts d'instance qui
    lisent encore l'etat du callee via l'ancien chemin Why.

## Objectif courant (mise a jour 2026-03-09 - diagnostic de preuve Kairos)
Fournir une chaine de diagnostic d'echec de preuve coherente entre:
- CLI;
- backend v2;
- protocole LSP;
- extension VS Code.

Livrables vises pour cette iteration:
- trace structuree par goal avec spans et diagnostic;
- JSON CLI stable pour iterer sans UI;
- dashboard VS Code branche sur ces traces;
- vue dediee `Explain Failure`;
- navigation Source / OBC / Why / VC / SMT / dump SMT.

## Methodologie (mise a jour 2026-03-09 - diagnostic de preuve Kairos)
1. Partir des donnees reelles disponibles dans `Pipeline_v2_indep`, pas d'une
   couche UI speculative.
2. Construire une trace typee unique et la propager:
   - runtime,
   - protocole,
   - LSP,
   - CLI,
   - extension.
3. Deriver la categorisation d'echec depuis des informations justifiables:
   - famille d'obligation backend,
   - statut solveur,
   - sequent Why3,
   - spans d'artefacts.
4. Valider en sequence par:
   - `npm run compile`,
   - `dune build` LSP/CLI/IDE,
   - cas CLI reels avec `--dump-proof-traces-json`.

## Etat courant (mise a jour 2026-03-09 - diagnostic de preuve Kairos)
- Fait:
  - modele `proof_trace` de bout en bout;
  - export CLI JSON `--dump-proof-traces-json`;
  - support CLI `--timeout-s` pour les runs de preuve/dump de traces;
  - analyse structuree des sequents Why3 pour classer le contexte pertinent
    sans heuristique purement lexicale;
  - instrumentation Why3 des hypotheses generees avec:
    - identifiant stable `hid`,
    - nature `hkind` (`pre` / `post`),
    - origine normalisee `origin:*`;
  - champs de diagnostic supplementaires:
    - `goal_symbols`,
    - `analysis_method`,
    - `unused_hypotheses`;
  - mode CLI borne pour les cas lourds:
    - `--proof-traces-failed-only`,
    - `--max-proof-traces`,
    - `--proof-traces-fast`,
    - `--proof-trace-goal-index`,
    - borne effective sur le nombre de goals prouves via `max_proof_goals`;
  - replay local borne sur les hypotheses instrumentees `hid` pour approximer
    un noyau d'echec minimal quand un goal reste non valide;
  - separation explicite dans le diagnostic entre:
    - noyau Kairos instrumente,
    - contexte auxiliaire Why3;
  - transport LSP via `outputsReady`;
  - panel VS Code `Explain Failure`;
  - dashboard branche sur `proof_traces`;
  - navigation vers Source / OBC / Why / VC / SMT / dump.
- Limites encore ouvertes:
  - le contexte minimal reste une analyse structurelle Why3, pas un unsat core
    ou une preuve explicative du solveur; le noyau d'echec actuel vient d'un
    replay glouton sur hypotheses Kairos instrumentees;
  - le ciblage se fait actuellement par `goal_index` de VC splittee, pas encore
    par `stable_id` directement cote pipeline.
  - sur les cas `ko` lourds, la borne CLI suit l'ordre des goals: il faut
    parfois augmenter `--max-proof-traces` pour atteindre un echec plus tardif.

## Objectif courant (mise a jour 2026-03-09 - chantier VS Code Kairos)
Transformer `extensions/kairos-vscode` en interface professionnelle exploitable
au quotidien, avec:
- parite fonctionnelle substantielle avec `bin/ide/obcwhy3_ide.ml` quand elle a
  du sens dans VS Code;
- rendu d'automates interactif de haut niveau;
- typage propre du protocole Kairos cote extension;
- integration VS Code native complete:
  - vues,
  - panneaux,
  - status bar,
  - commandes,
  - settings,
  - code lenses,
  - restauration de session.

## Methodologie (mise a jour 2026-03-09 - chantier VS Code Kairos)
1. Partir d'un audit factuel des quatre pieces:
   - extension,
   - LSP,
   - protocole,
   - UI native.
2. Refondre d'abord l'architecture du client VS Code:
   - types partages,
   - etat applicatif,
   - orchestration des runs,
   - providers,
   - webviews.
3. Reutiliser le protocole existant partout ou il suffit; etendre seulement ce
   qui manque pour:
   - exports propres,
   - rendu automates plus riche,
   - observabilite des runs.
4. Garder un theme clair par defaut dans les webviews, mais derive des couleurs
   depuis les variables de theme VS Code.
5. Valider a chaque etape par:
   - `npm run compile` dans l'extension,
   - `dune build` si le protocole/LSP change,
   - smoke tests des commandes principales.

## Ecarts prioritaires (mise a jour 2026-03-09 - chantier VS Code Kairos)
1. Eliminer les `any` et la monolithie de `src/extension.ts`.
2. Ajouter `Reset`, `Cancel run`, historique local et barre de statut.
3. Construire quatre panneaux de travail:
   - Automata,
   - Goals dashboard,
   - Artifacts workspace,
   - Eval playground.
4. Completer les settings et l'integration editeur.
5. Produire une documentation utilisateur et technique exhaustive versionnee,
   puis en generer un PDF maintenu dans le depot.

## Etat d'avancement (mise a jour 2026-03-09 - chantier VS Code Kairos)
- Fait:
  - audit detaille versionne dans `extensions/kairos-vscode/AUDIT_2026-03-09.md`;
  - refonte modulaire et typee du client VS Code;
  - ajout du studio Automata, du dashboard de preuve, de l'espace Artifacts,
    du playground Eval, de la vue Runs, du pipeline view et d'un compare view;
  - ajout de `Cancel Run`, `Reset State`, code lenses, keybindings, settings et
    historique local;
  - ajout de persistance workspace, export HTML et tasks VS Code;
  - documentation complete en Markdown + PDF dans `docs/`.
- Reste a pousser ulterieurement si l'on veut depasser cette iteration:
  - modeliser un protocole de graphe plus semantique que le couple DOT/SVG;
  - rejouer la validation `dune build` dans un shell ou `dune` est disponible;
  - eventuellement packager et tester la `.vsix` dans une extension host
    interactive.

## Objectif courant (mise a jour 2026-03-09)
Finaliser la bascule du runtime sur le pipeline externe:
- Spot pour la construction d'automates de surete;
- Z3 pour la simplification FO modulo symboles non interpretes;
- suppression des anciens modules maison devenus morts.

## Methodologie (mise a jour 2026-03-09)
1. Garder une seule entree pour la generation d'automates dans
   `Automaton_engine`, branchee sur Spot.
2. Conserver seulement les conversions et adaptateurs encore utilises par le
   pipeline aval (gardes DNF, etat `bad`, rendu DOT).
3. Retirer du build et du depot les modules legacy non references.
4. Valider par compilation `dune build` avant toute autre extension.

## Objectif courant (mise a jour 2026-03-09 - plomberie IDE/runtime)
Reduire la maintenance du projet en externalisant la plomberie generique:
- transport JSON-RPC sur `jsonrpc`;
- objets LSP standard sur `lsp`;
- emission JSON AST sur `Yojson.Safe.t` au lieu de concatenation de chaines.

## Methodologie (mise a jour 2026-03-09 - plomberie IDE/runtime)
1. Garder la logique metier et le dispatch Kairos, mais remplacer le transport
   et les structures standard par les bibliotheques dediees.
2. Limiter le changement de protocole aux objets standard LSP pour ne pas casser
   le protocole IDE specifique Kairos en une seule passe.
3. Verifier par `dune build` puis par un echange `initialize/shutdown` minimal.

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

## Objectif courant (2026-03-08 - resettable_delay concret)
Ancrer la formalisation et le papier dans un exemple Kairos reel:
- ecrire `resettable_delay` dans le langage source Kairos;
- le faire passer dans le pipeline pour obtenir automates residuels, produit,
  clauses, OBC+ et code Why3;
- reutiliser ces artefacts pour documenter concretement le passage
  specification safety -> automates -> clauses/triples -> backend Why3.

### Methodologie active
1. Definir un exemple `resettable_delay` avec:
   - une hypothese d'entree non triviale (`reset => x = 0`);
   - une garantie en trois branches (`reset`, `post-reset`, `delay ordinaire`);

## Objectif courant (2026-03-09 - migration Spot)
Remplacer le compilateur d'automates de surete maison par Spot sans casser le
reste du pipeline Kairos, qui attend encore:
- des automates deterministes complets;
- des gardes sous forme DNF sur les atomes Kairos;
- un etat `bad` explicite detecte via `LFalse`.

### Methodologie active
1. Garder l'interface publique `Automaton_engine` stable pour ne pas toucher au
   produit, a l'instrumentation et aux obligations.
2. Ajouter un backend Spot CLI:
   - verification explicite du caractere safety via `ltlfilt --safety`,
   - generation HOA via `ltl2tgba -M -D -C -H`,
   - import des labels HOA vers des gardes DNF Kairos.
3. Normaliser la sortie Spot pour recreer la convention interne Kairos:
   - etats acceptants conserves comme etats "sains",
   - region rejetante repliee sur un unique etat `bad`,
   - boucle `true` sur `bad` pour conserver la semantique absorbante attendue.
4. Conserver un chemin `legacy` activable par variable d'environnement pour
   comparer les comportements pendant la transition.

### Validation prevue
1. `opam exec -- dune build`
2. smoke tests CLI sur:
   - `delay_int.kairos` via `--dump-dot`,
   - `resettable_delay.kairos` via `--dump-obc`,
   - `credit_balance_monitor.kairos` via `--dump-product`.

## Objectif courant (2026-03-09 - simplification FO via Z3)
Ajouter un backend de simplification de formules de premier ordre qui exploite
Z3 pour les symboles non interpretes, sans exiger de nouvelle API OCaml liee au
solver et sans destabiliser le pipeline existant.

### Methodologie active
1. Conserver les simplifications syntaxiques locales deja presentes.
2. Ajouter un module `Fo_simplifier` qui:
   - traduit les formules Kairos en SMT-LIB,
   - encode les `FPred` et `pre_k` comme symboles non interpretes,
   - interroge Z3 seulement pour des questions boolennes stables:
     validite, contradiction, implication.
3. Restreindre les remplacements a:
   - `true` / `false`,
   - elimination de sous-formules redondantes,
   - repli sur des sous-formules existantes.
4. Brancher cette simplification:
   - dans l'affichage OBC/Why3 pour des formules plus lisibles,
   - dans les gardes du produit pour reduire les formules evidemment
     redondantes avant les tests de recouvrement.

### Validation prevue
1. `opam exec -- dune build`
2. smoke tests CLI sur:
   - `delay_int.kairos` via `--dump-obc`,
   - `resettable_delay.kairos` via `--dump-obc`,
   - `credit_balance_monitor.kairos` via `--dump-product`.

## Objectif courant (2026-03-09 - reduction de la plomberie LSP/JSON)
Remplacer la serialisation JSON artisanale et le framing JSON-RPC maison par
des bibliotheques de l'ecosysteme OCaml, tout en gardant le protocole IDE
Kairos compatible avec les clients existants.

### Methodologie active
1. Basculer le serveur LSP sur `jsonrpc` et `lsp` pour:
   - le framing `Content-Length`,
   - les paquets `request/response/notification`,
   - les types standard (`InitializeResult`, diagnostics, locations, symboles).
2. Remplacer la production JSON manuelle du dump AST par des valeurs
   `Yojson.Safe.t`.
3. Reimplementer `protocol/lsp_protocol.ml` via `ppx_deriving_yojson` pour les
   payloads IDE, en conservant l'API historique `yojson_of_*` / `*_of_yojson`
   afin de limiter le churn dans le reste du projet.
4. Garder un decodeur manuel seulement la ou une contrainte de compatibilite
   l'impose encore explicitement (`config.engine` par defaut).

### Validation prevue
1. `opam exec -- dune build`
2. smoke test LSP minimal sur `initialize`, `shutdown`, `exit`
3. verification des conversions IDE via les appels existants du client
   `ide_lsp_process_client`.
4. dans un second passage, typer aussi:
   - les notifications Kairos `outputsReady`, `goalsReady`, `goalDone`,
   - les reponses LSP standard encore construites a la main dans
     `kairos_lsp.ml`.
5. aligner enfin le client IDE sur le meme socle `jsonrpc` + `lsp`, au moins
   pour:
   - le transport,
   - les notifications/documents standard,
   - les principales reponses `hover`, `definition`, `references`,
     `completion`, `formatting`.
6. factoriser ensuite les payloads Kairos specifiques dans `Lsp_protocol` pour
   eviter la duplication de schema entre serveur, client IDE et documentation:
   - `outline`,
   - `goalsTreeFinal` / `goalsTreePending`,
   - passes backend,
   - notifications de run.
   - un invariant utilisateur piecewise sur la memoire.
2. Generer avec les executables du depot:
   - exclusivement avec `_build/default/bin/cli/main_v2.exe`;
   - automates (`--dump-automata`);
   - produit (`--dump-product`);
   - carte des clauses (`--dump-obligations-map`);
   - OBC+ abstrait (`--dump-obc --dump-obc-abstract`);
   - Why3 (`--dump-why`) et verification conditions (`--dump-why3-vc`).
3. Evaluer honnetement la validation backend:
   - succes d'extraction;
   - statut de la preuve automatique Why3/Z3 sous budget borne.
4. Integrer les resultats dans le papier et dans une note de reproduction locale.

## Suite prevue
- maintenir une UI automates unique et minimale:
  - vues graphiques `Program`, `Assume`, `Guarantee`, `Product`;
  - pas d'onglet de diagnostic/instrumentation dans cette fenetre;
  - theme clair par defaut tant qu'aucune preference explicite n'est chargee.
- maintenir un packaging opam exploitable pour le depot:
  - pin local via `opam pin add kairos . --working-dir`;
  - installation reelle des binaires `kairos`, `kairos-lsp`, `kairos-ide`;
  - verification par `which` dans le switch actif.
- garder l'extension VS Code robuste a l'absence temporaire du LSP:
  - activation sans blocage sur `client.start()`;
  - commandes toujours enregistrees;
  - erreurs utilisateur explicites seulement lors des actions dependantes du
    serveur.
- pousser l'architecture automates vers un mode `image-first`:
  - le backend/LSP doit exposer directement les rendus des graphes utiles;
  - l'extension VS Code ne doit plus afficher le DOT comme surface utilisateur;
  - le DOT reste un format d'export technique seulement.
- stabiliser la section technique du papier autour de l'exemple reel `resettable_delay`;
- ameliorer si besoin l'automatisation Why3 sur cet exemple en analysant les
  premiers goals bloquants.
- maintenir un chemin outillage unique via `main_v2.exe` pour tous les artefacts
  cites dans le papier et la documentation technique.
- finaliser la couche "native unsat core" pour les diagnostics cibles:
  - emission SMT nommee sur hypotheses Kairos instrumentees;
  - recuperation et remappage des cores solveur;
  - exposition CLI/LSP/UI;
  - documentation honnete de la portee: utile sur goals `unsat`, fallback
    necessaire pour les goals reellement en echec.
- faire remonter les vrais `failure` avec plus de precision:
  - distinguer `invalid`, `unknown`, `timeout`, `solver_error`, `failure`;
  - sonder une VC ciblee via le solveur natif pour recuperer, quand possible,
    un modele/contre-exemple;
  - documenter explicitement les cas ou aucun modele n'est disponible.
- maintenir une documentation d'installation simple et exploitable:
  - installation opam;
  - outillage Why3/Z3/Graphviz;
  - installation VS Code via `.vsix`;
  - configuration LSP de secours via `dune`.
- stabiliser la livraison des automates dans VS Code par ressources webview
  locales:
  - ne plus injecter les PNG en `data:` dans le script HTML si cela fragilise
    le rendu;
  - copier les graphes rendus dans `globalStorage`;
  - servir ces fichiers via `webview.asWebviewUri(...)`;
  - garder l'interdiction du DOT comme surface ou fallback utilisateur.
- maintenir une experience d'edition VS Code de base complete:
  - definition du langage `kairos`;
  - coloration syntaxique TextMate pour les constructions centrales du DSL;
  - couverture explicite des sections, contrats, transitions, operateurs
    temporels, types, commentaires et affectations.
- rendre les commandes et panneaux VS Code resilients au focus webview:
  - ne pas dependre uniquement de `activeTextEditor` pour retrouver le fichier
    source Kairos courant;
  - reutiliser `state.activeFile` quand le focus est sur `Dashboard`,
    `Explain Failure` ou `Automata`.
- garder le chemin standard `Kairos: Prove` rapide et progressif:
  - ne pas executer les diagnostics lourds (native probe, replay/minimization)
    sur tous les goals dans le flux global;
  - reserver ces diagnostics aux chemins focalises ou aux exports dedies;
  - publier `outputsReady` et `goalsReady` avant la fin complete de la preuve,
    pour que Dashboard et Artifacts deviennent utiles pendant le run.
- sur les noeuds deja instrumentes par le monitor:
  - ne pas dupliquer dans Why des obligations deja abaissees sur les
    transitions OBC;
  - en particulier, ne pas recycler les `requires` de transition en
    `ensures` globaux de `step`;
  - ne pas repropager globalement les contrats monitor/garantie si leur
    semantique est deja encodee dans les transitions instrumentees;
  - valider cette propriete sur des cas de regression reels comme
    `tests/ok/inputs/delay_int.kairos`.
- migration vers le pipeline du kernel, sans toucher a Rocq:
  - etape 1: introduire dans Kairos un IR intermediaire explicite
    `programme reactif / automates / produit / clauses`;
  - garder cet IR abstrait:
    il ne doit pas dependre des details Why, OBC, LSP ou VS Code;
  - utiliser l'IR pour exposer et diagnostiquer le pipeline sans encore
    remplacer brutalement le backend Why;
  - rebrancher Why sur cet IR seulement dans une etape ulterieure, apres
    validation sur des cas reels.
- migration vers le pipeline du kernel, etape 2 en cours:
  - faire traverser `product_kernel_ir` jusqu'au backend Why;
  - commencer par une consommation additive et verifiable:
    - clauses de propagation/safety -> postconditions Why annotees;
    - clauses d'initialisation -> goals Why separes;
  - conserver l'ancien chemin en parallele tant que la regression n'est pas
    exclue sur les cas reels;
  - verifier explicitement sur `delay_int.kairos` et autres cas de reference
    que cette consommation de l'IR n'introduit pas de nouveaux `failure`;
  - puis reduire progressivement les reconstructions Why issues de
    `t.ensures`/`state_post` quand un noeud monitorise dispose deja d'un
    `kernel_ir`, afin que la preuve suive davantage le produit explicite que le
    programme instrumente;
  - faire la meme migration cote `pre`:
    - ne pas supprimer brutalement les hypotheses d'entree;
    - les regenerer depuis les etats du produit explicite comme
      `Kernel source state invariant`;
    - verifier sur `delay_int.kairos` que ces hypotheses suffisent a remplacer
      le chemin `transition_requires_pre`;
  - une fois cette bascule stable, vider aussi `link_terms_pre/post` sur les
    noeuds monitorises, pour supprimer les derniers reliquats locaux du chemin
    instrumente;
  - garder ensuite un chantier distinct pour les cas avec instances:
    - `instance_invariants`
    - `instance_delay_links_*`
    - autres liens inter-noeuds qui ne peuvent pas encore etre elimines sans
      modelisation explicite dans l'IR kernel-compatible;
  - etendre donc `product_kernel_ir` avec une couche abstraite de relations
    d'instance avant de supprimer ces blocs de `why_contracts`;
  - une fois cette couche branchee, ajouter ou identifier un cas de test reel
    avec `instances/call` pour valider la migration de bout en bout;
  - si une regression apparait, corriger d'abord la projection Why des pas du
    produit avant d'aller plus loin;
  - ne pas toucher a Rocq ni aux enonces du kernel sans confirmation
    explicite.
- reprise `instances/call`:
  - introduire d'abord dans `product_kernel_ir` des types separes pour:
    - `callee_tick_abi_ir`
    - `call_site_instantiation_ir`
  - reutiliser `clause_fact_ir` pour les faits d'appel;
  - fournir un rendu textuel et un exemple jouet avant toute compilation de
    `SCall`;
  - construire ensuite effectivement ces deux objets depuis le programme
    normalise:
    - ABI par callee appele;
    - instanciation par site d'appel;
    - cas de resume derives des transitions normalisees du callee;
  - seulement ensuite:
    - brancher un premier cas reel avec `instances/call`;
    - compiler `SCall` a partir de ces deux objets.
  - un premier cas reel a maintenant ete ajoute:
    `tests/ok/inputs/delay_int_instance.kairos`;
  - ce cas valide le remplissage de:
    - `callee_tick_abis`
    - `call_site_instantiations`
  - il expose maintenant un bug backend separe a traiter:
    la projection Why des champs du record de l'instance appelee;
  - une correction partielle de `SCall` a deja ete faite:
    - `step` est maintenant traite comme `unit`;
    - les sorties sont relues dans l'instance apres appel;
  - le verrou restant est maintenant:
    `Delay_core.__delay_core_outv` non resolu comme projection Why.
  - mise a jour 2026-03-11:
    - ce verrou de projection Why est traite;
    - le blocage suivant etait en fait semantique:
      des branches produit mortes survivaient dans l'IR et recreaient des VCs
      absurdes (`goal ... : false`, etats `Aut2`);
    - `product_kernel_ir` filtre maintenant:
      - les `product_states` non vivants;
      - les `product_steps` dont le source state est deja mort;
    - le fixture reel
      `tests/ok/inputs/delay_int_instance.kairos`
      revient a `0 failed traces` en validation CLI standard.

- prochaine etape:
  - nettoyage realise:
    - la couche texte `product_debug.render_obligation_lines` n'affiche plus
      les obligations `Bad_guarantee` tautologiques ou deja mortes;
    - `--dump-obligations-map` ouvre maintenant directement sur
      `-- Kernel-compatible pipeline IR --`;
  - builds sequentiels verifies:
    - `bin/cli/main.exe`
    - `bin/lsp/kairos_lsp.exe`
    - `bin/ide/obcwhy3_ide.exe`
  - suite du chantier:
    - reprendre la migration vers l'IR unique:
    - reduire encore les reliquats du chemin OBC annote;
    - garder `instances/call` sur le nouvel IR abstrait;
    - ne pas toucher a Rocq sans confirmation explicite.
  - contrainte precise ajoutee:
    - le backend Why ne doit activer le chemin `kernel-first` que si le
      `kernel_ir` contient de vrais `product_steps`;
    - si le produit explicite est encore partiel (`steps=0`), il faut
      conserver le fallback sur l'ancien chemin jusqu'a migration complete;
  - etat verifie au 2026-03-11:
    - `delay_int.kairos`: OK
    - `resettable_delay.kairos`: OK
    - `delay_int_instance.kairos`: OK
  - mise a jour 2026-03-11 (suite):
    - l'IR a ete enrichi pour les cas ou l'exploration explicite restait vide;
    - si les etats vivants fournissent une correspondance unique
      `prog_state -> product_state`, `product_kernel_ir` synthétise maintenant
      un squelette conservatif de `product_steps`;
    - `resettable_delay.kairos` produit ainsi de vrais pas et clauses de
      propagation dans l'IR;
    - le fallback Why n'est plus necessaire pour ce cas.

  - prochaine etape:
  - factorisation realisee:
    - l'IR porte maintenant explicitement:
      - `product_step_origin`
      - `product_coverage`
    - le backend Why s'appuie sur
      `Product_kernel_ir.has_effective_product_coverage`;
  - suite du chantier:
    - continuer a remplacer les reliquats du chemin OBC annote **cas par cas**,
      uniquement quand l'IR dispose d'assez d'information semantique;
    - prochaine cible:
      - reduire encore dans `why_contracts.ml` les blocs historiques
        redondants sur les noeuds en `CoverageExplicit` ou `CoverageFallback`;
      - garder les garde-fous CLI sur:
        - `delay_int.kairos`
        - `resettable_delay.kairos`
        - `delay_int_instance.kairos`
  - mise a jour 2026-03-11:
    - premier nettoyage supplementaire realise dans `why_contracts.ml`:
      elimination de calculs morts seulement;
    - les trois garde-fous CLI restent verts;
    - prochaine reduction a viser:
      des blocs encore actifs mais redondants, par exemple certaines liaisons
      auxiliaires conditionnees par `CoverageExplicit/CoverageFallback`.
  - mise a jour 2026-03-11 (suite):
    - `output_links` a ete retire du chemin `kernel-first`;
    - les trois garde-fous CLI restent verts;
    - prochaine reduction possible:
      - `link_terms_pre/post`
      - ou une partie de `instance_invariants`
      sous validation stricte des memes cas de garde.
  - mise a jour 2026-03-11 (suite 2):
    - `link_terms_pre/post` etaient deja sans effet sur le chemin IR;
    - `instance_invariants` est maintenant retire du chemin
      `CoverageExplicit/CoverageFallback`;
    - les trois garde-fous CLI restent verts;
    - prochaine cible de reduction:
      - `transition_requires_pre_terms`
      - `transition_requires_post`
      - ou `transition_post_to_pre`
      avec la meme discipline de validation.
  - mise a jour 2026-03-11 (suite 3):
    - le fallback legacy des liens/invariants d'instance est maintenant
      extrait dans `compute_legacy_link_fallback`;
    - le flux principal de `build_contracts_runtime_view` ne porte plus ce
      bloc inline;
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      reduire encore le contenu interne de ce fallback isole, ou supprimer
      entierement certaines branches devenues vides sur le chemin IR.
  - mise a jour 2026-03-11 (suite 4):
    - le helper `legacy_link_fallback` a ete amincit;
    - les champs structurellement vides ne sont plus transportes dans ce
      record local;
    - la compatibilite diagnostique est provisoirement preservee via des
      listes vides explicites au point d'appel;
    - prochaine cible:
      simplifier `why_diagnostics` pour enlever aussi cette ABI residuelle.
  - mise a jour 2026-03-11 (suite 5):
    - `why_diagnostics` a ete simplifie;
    - les categories legacy toujours vides ont ete retirees du
      `label_context`;
    - `why_contracts` n'alimente plus ces champs artificiellement;
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      identifier le prochain residu semantique reel du fallback legacy,
      plutot qu'une simple structure de labels.
  - mise a jour 2026-03-11 (suite 6):
    - les residus toujours vides `pre_contract_user`, `pre_invf`,
      `post_invf` ont ete retires du calcul Why actif;
    - `post_contract_user` reste conserve, car encore semantiquement utile sur
      le chemin legacy non kernel-first;
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      un bloc legacy encore effectivement actif dans `why_contracts.ml`,
      probablement autour des `transition_requires_*` ou de `state_post`.
  - mise a jour 2026-03-11 (suite 7):
    - `transition_post_to_pre` a ete retire comme doublon semantique de
      `post_contract`;
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      examiner si `transition_requires_post` ou une partie de `state_post`
      restent encore redondants sur le chemin legacy.
  - mise a jour 2026-03-11 (suite 8):
    - `transition_requires_post` et `state_post` ne sont plus transportes
      comme blocs separes;
    - ils sont maintenant absorbes dans:
      - `legacy_post_contract`
      - `pure_post`
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      voir si `state_post_terms` et `state_post_terms_vcid` peuvent etre
      rapproches encore davantage du chemin labels/vcid sans conserver de
      structure legacy supplementaire.
  - mise a jour 2026-03-11 (suite 9):
    - cette derniere structure `legacy` a ete eliminee de `why_contracts.ml`;
    - les types et helpers sont maintenant nommes comme composants normaux du
      chemin runtime Why;
    - verification structurelle:
      `rg "legacy_" lib_v2/runtime/backend/why` ne retourne plus rien;
    - les trois garde-fous CLI restent verts.
  - mise a jour 2026-03-11 (suite 10):
    - la production des contrats a ete extraite dans
      `why_contract_plan.ml`;
    - `why_contracts.ml` devient un adaptateur/assembleur Why plus mince;
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      voir si la meme logique de decoupage peut maintenant etre appliquee a
      une partie du runtime d'emission Why (`emit` / `why_core`) ou si le
      prochain gain utile est plutot dans la construction amont de
      `Why_runtime_view`.
  - mise a jour 2026-03-11 (suite 11):
    - la logique de planification des appels a ete extraite de `emit.ml` dans
      `why_call_plan.ml`;
    - `Why_runtime_view` porte maintenant des `call_sites` explicites par
      transition;
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      pousser encore en amont, dans `Why_runtime_view`, la structure
      necessaire a l'execution Why afin de reduire encore le travail de
      `why_core` et de l'emission finale.
  - mise a jour 2026-03-11 (suite 12):
    - `Why_runtime_view` porte maintenant aussi des `action_blocks`
      explicites par transition;
    - `why_core.ml` compile ces blocs generiquement au lieu de reposer sur
      trois champs speciaux connus en dur;
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      voir si l'on peut pousser encore plus loin la preparation runtime en
      amont, par exemple en materialisant des branches d'etat plus proches de
      l'emission finale, sans injecter de details Why3 dans l'IR.
  - mise a jour 2026-03-11 (suite 13):
    - `Why_runtime_view` porte maintenant des `state_branches` explicites;
    - `why_core.ml` expose `compile_runtime_view` et ne depend plus d'un
      regroupement local des transitions;
    - `emit.ml` ne monte plus lui-meme le corps `step` a partir des groupes;
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      voir si certaines preparations encore derivees de `Ast.stmt` dans la
      vue runtime peuvent devenir des objets runtime plus abstraits, tout en
      restant independants de Why3.
  - mise a jour 2026-03-11 (suite 14):
    - cette cible a ete executee:
      `Why_runtime_view` porte maintenant une IR runtime d'actions
      (`runtime_action_view`);
    - `why_core.ml` compile des actions runtime, plus des `Ast.stmt`;
    - les ponts `runtime -> Ast` ont ete centralises dans
      `Why_runtime_view`;
    - `why_contract_plan.ml` et `why_call_plan.ml` reutilisent davantage les
      informations runtime deja calculees (`call_sites`, `has_instance_calls`);
    - les trois garde-fous CLI restent verts;
    - prochaine cible:
      consolider la couverture sur des cas `instances/call` plus riches et
      continuer a reduire les dernieres reconstructions AST encore
      necessaires pour des modules de compatibilite.
  - mise a jour 2026-03-11 (suite 15):
    - ajout d'un fixture `instances/call` plus riche:
      `delay_int2_instance.kairos`;
    - campagne CLI elargie verte sur 4 cas:
      `delay_int`, `resettable_delay`, `delay_int_instance`,
      `delay_int2_instance`;
    - les couches d'architecture cibles ont ete explicitees dans
      `ARCHITECTURE_PIPELINE_LAYERS.md`;
    - prochaine cible:
      soit pousser encore l'abstraction runtime pour les modules Why de
      compatibilite restants, soit elargir la couverture a des cas d'appel
      encore plus riches (guards, appels conditionnels, plusieurs sorties si le
      langage le permet).
  - mise a jour 2026-03-11 (suite 16):
    - `why_runtime_view` porte maintenant des metadonnees de callee explicites
      (`callee_summaries`);
    - `why_call_plan.ml` et `why_contract_plan.ml` n'ont plus besoin
      d'introspecter directement les nœuds callees via `find_node`;
    - `why_contracts.ml` s'appuie davantage sur cette vue runtime et moins sur
      des reconstructions `runtime -> Ast.transition`;
    - un vrai bug de refactorisation a ete corrige dans `why_core.ml`:
      la mise a jour de `st` vers `dst_state` avait disparu du rendu Why;
    - un correctif complementaire a ete applique a la derivation de
      `output_links`, qui doit prendre la derniere affectation pertinente dans
      le corps et non uniquement la derniere instruction du bloc;
    - etat honnete:
      l'architecture est nettement plus propre, mais la robustesse de certains
      runs CLI courts a `3s` reste a consolider, surtout sur
      `resettable_delay.kairos`.
  - mise a jour 2026-03-11 (suite 17):
    - tentative de specialisation du runtime Why a partir d'un hint
      `known_monitor_ctor` derive du produit explicite;
    - essai non concluant:
      la projection etait trop grossiere et a deteriore `resettable_delay`;
    - decision:
      retirer cette specialisation et conserver seulement:
      - les metadonnees de callee dans `why_runtime_view`;
      - la simplification locale sous garde connue;
      - les corrections de codegen (`st <- dst_state`, `output_links`);
    - prochaine cible si l'on reprend ce point:
      derive un hint monitor precis au niveau du produit explicite par pas
      reel, pas par simple paire `(src, dst)` de transition programme.
  - mise a jour 2026-03-11 (suite 18):
    - extension de la suite `tests/ok/inputs` avec 10 nouveaux cas de safety;
    - principe retenu:
      ne pas ajouter seulement des `G p` triviaux, mais couvrir:
      - `G (p => G q)`,
      - `G (p => X G q)`,
      - `X G`,
      - `X X G`,
      - conjunctions internes,
      - cas `instances/call`;
    - methode:
      - partir de schemas concrets simples a implementer proprement;
      - valider chaque fichier en CLI avec export JSON structure des goals
        failed;
      - simplifier immediatement toute formule qui revele une limite actuelle
        du frontend Spot/AP plutot que garder un faux bon cas;
    - resultat:
      10 cas ajoutes et tous valides a `failed=0`.
  - mise a jour 2026-03-11 (suite 19):
    - raffinement qualitatif des 10 nouveaux cas apres retour utilisateur;
    - principe retenu:
      ne pas se contenter d'exemples minimaux qui recalculent directement la
      sortie a chaque tick;
    - methode:
      favoriser des structures avec:
      - etat d'initialisation;
      - etat d'attente;
      - etat stable/puits/latch;
      - dynamique durable apres un evenement declencheur;
    - objectif:
      que les automates et obligations exercent de vrais changements de regime,
      et pas seulement des boucles triviales.
  - mise a jour 2026-03-11 (suite 20):
    - suppression complete de la suite `tests/ko` a la demande explicite de
      l'utilisateur;
    - methode:
      suppression directe de tous les fichiers de `tests/ko`, y compris le
      `dune` local et les fixtures d'entree;
    - verification:
      `find tests/ko -type f` vide apres operation.
  - mise a jour 2026-03-11 (suite 21):
    - reconstruction d'une base `ko` systematique a partir de toute la suite
      `ok`;
    - schema:
      pour chaque fichier `ok`, generer trois variantes:
      - `bad_spec`
      - `bad_invariant`
      - `bad_code`
    - choix methodologique:
      preferer des variantes `ko` structurellement negatives et reproductibles
      a des mutations semantiques trop faibles qui peuvent rester vertes;
    - consequence:
      `bad_invariant` et `bad_code` utilisent des erreurs garanties
      (symboles non definis) dans la zone demandee;
    - total genere:
      `81` cas `ko` pour `27` cas `ok`.
  - mise a jour 2026-03-11 (suite 22):
    - campagne de validation stricte a `3s` par obligation sur toute la base
      `ok/ko`;
    - objectif methodologique precise:
      ne plus raisonner sur quelques cas manuels seulement, mais faire converger
      le code et les fixtures ensemble jusqu'a obtenir:
      - `ok` verts;
      - `ko` jamais verts.
    - corrections de methode retenues:
      - pour `ok`:
        corriger d'abord le backend Why et l'emission des obligations plutot
        que d'augmenter les timeouts;
      - pour `ko`:
        quand une mutation negative reste verte, considerer en premier que le
        fixture est mal construit, puis regenerer une variante structurellement
        negative.
    - strategie finale `bad_spec`:
      abandon des mutations trop faibles ou "hors AP";
      adoption d'une contradiction de safety sur output reel:
      `G ((o = o) and not (o = o))`.
    - reserve explicite:
      conserver une validation ciblee repetee sur les cas sensibles
      (notamment `ack_cycle`) tant qu'un sweep complet unique peut encore
      montrer une fluctuation de premiere passe.
  - mise a jour 2026-03-11 (suite 23):
    - cloture de la campagne de validation avec `5s` maximum par obligation;
    - objectif:
      supprimer la derniere reserve sur `ack_cycle` et produire une
      certification finale exploitable avant audit d'alignement Rocq;
    - correctif retenu:
      ne plus emettre `OriginInitAutomatonCoherence` comme goal Why universel,
      car ce n'est pas une propriete vraie d'un `vars` arbitraire;
    - resultat:
      `tests/ok/inputs` tous verts, `tests/ko/inputs` aucun faux vert.
  - mise a jour 2026-03-11 (suite 24):
    - audit d'alignement implementation / formalisation Rocq sans modifier
      `kairos-kernel`;
    - these methodologique:
      separer le jugement "la theorie est-elle fautive ?" de
      "l'implementation est-elle encore transitoire ?";
    - resultat de l'audit:
      les ecarts restants sont cote implementation;
      la formalisation reste coherente et suffisamment abstraite;
    - causes implementation restantes:
      - absence de fait explicite `assume_state` dans les clauses generees;
      - modelisation encore imparfaite de l'initialisation;
      - produit explicite encore incomplet sur certains cas (`resettable_delay`);
      - presence d'un mecanisme de fallback sans equivalent direct dans Rocq;
    - document de reference:
      [ALIGNMENT_KAIROS_KERNEL_AUDIT.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/ALIGNMENT_KAIROS_KERNEL_AUDIT.md)

  - mise a jour 2026-03-11 (suite 25):
    - objectif immediat:
      revenir a un backend Why stable apres une tentative trop precoce
      d'introduire l'etat explicite de l'automate d'assumption;
    - regle methodologique retenue:
      ne conserver dans le chemin critique de preuve que les changements
      effectivement robustes a `5s`, et documenter les chantiers d'alignement
      restants plutot que de laisser des demi-correctifs regressifs;
    - consequence:
      rollback du support partiel `FactAssumeState` / `__assume_state` dans le
      backend Why;
    - conservation du correctif general deja valide:
      suppression de l'emission des goals Why universels d'init d'automate;
    - validation finale retenue:
      - sweep `ok/ko` a `5s`;
      - puis rerun cible de tous les residus identifies jusqu'a stabilisation;
      - correction du generateur `bad_spec` pour tolerer l'alignement
        `ensures  :`.
    - resultat methodologique:
      architecture plus claire et base `ok/ko` a nouveau exploitable, sans
      confondre un objectif d'alignement futur avec une correction prematuree
      du chemin critique.

## Mise au point sur les variantes `__bad_code`

- Regle retenue:
  - une variante `__bad_code` doit rester un programme Kairos bien forme et
    executable;
  - l'erreur doit etre semantique: mauvaise mise a jour, mauvaise sortie,
    comportement divergent, mais pas symbole inconnu ou programme irrecevable.

- Strategie actuellement appliquee:
  - preferer une mutation sur une transition non `init`;
  - remplacer les affectations de sorties pertinentes par une valeur constante
    fausse et bien typee;
  - pour les `call`, surcharger la sortie du noeud appelant juste apres l'appel;
  - traiter les fichiers multi-noeuds noeud par noeud pour respecter les
    interfaces locales.

- Limite a garder en tete:
  - si une variante `__bad_code` bien formee reste prouvee `valid`, cela ne
    doit plus etre interprete comme un probleme de generation de fixture mais
    comme un signal sur la couverture reelle des obligations ou sur la
    compilation de la specification.

## Extension de la base `ok/ko` sur `next` + `weak until`

- Ajouter explicitement des exemples de la forme:
  - `next always (phi => (psi W chi))`
- Viser des cas avec:
  - latch / fenetre active
  - sortie maintenue
  - bundle de sorties
- Si une formule se revele trop forte au premier tick d'entree dans la
  fenetre, preferer raffiner sa premisse (`prev ... = 1`) plutot que
  d'introduire un programme artificiellement plus complique.

## Decouplage de la campagne generale et de la campagne `instances/call`

- Objectif pratique immediat:
  - continuer a progresser sur la robustesse generale du pipeline tout en
    isolant clairement le chantier encore instable de la preuve modulaire des
    appels.

- Strategie retenue:
  - maintenir les suites historiques `tests/ok/inputs` et `tests/ko/inputs`
    pour compatibilite;
  - introduire en parallele deux sous-suites de travail:
    - `tests/without_calls/{ok,ko}/inputs`
    - `tests/with_calls/{ok,ko}/inputs`

- Regle de classement:
  - `with_calls`:
    - tout exemple utilisant `call` ou `import`;
    - ainsi que les noeuds support qu'un caller modularise doit compiler en
      `.kobj`;
  - `without_calls`:
    - tout le reste de la regression.

- Usage de validation:
  - valider le socle general avec:
    - `scripts/validate_ok_ko.sh <repo> 5 without_calls`
  - valider le sous-systeme modular calls avec:
    - `scripts/validate_ok_ko.sh <repo> 5 with_calls`
  - obtenir les deux rapports separes avec:
    - `scripts/validate_ok_ko.sh <repo> 5 split`

- Interpretation methodologique:
  - un vert `without_calls` ne valide pas encore la modularite des appels;
  - un rouge `with_calls` ne doit plus bloquer l'evaluation du reste de la
    chaine;
  - la cloture finale du chantier global exigera malgre tout de rerun aussi la
    campagne `legacy`, une fois le backend Why3 des `call` stabilise.
  - inversement, `without_calls` doit lui aussi etre reverifie honnetement par
    preuve apres chaque split: le decouplage des campagnes ne doit pas masquer
    d'anciens faux verts / faux rouges sans appels.

- Gestion des faux verts persistants hors appels:
  - lorsqu'une famille `__bad_code` reste `valid` malgre plusieurs mutations
    semantiquement fausses, ne pas la laisser dans la regression active;
  - la deplacer dans `tests/quarantine/` avec une note expliquant pourquoi elle
    n'est plus discriminante aujourd'hui;
  - ne reintroduire ces cas dans `ok/ko` qu'apres correction backend ou
    regeneration fiable des variantes.
  - maintenir un tableau de verite explicite:
    - faux verts encore reproductibles;
    - cas redevenus `INVALID`;
    - mutations finalement non discriminantes au regard de la spec.

- Discipline de validation:
  - considerer les rapports de campagne comme valides seulement une fois les
    fichiers de sortie ecrits atomiquement et la campagne terminee;
  - ne pas inferrer une regression backend a partir d'un TSV partiel ou ecrase
    par un rerun;
  - pour un doute sur un `ok`, rejouer le cas unitairement avec
    `--dump-proof-traces-json --proof-traces-failed-only` avant toute
    conclusion.

- Garde-fous issus de la formalisation Rocq (`kairos-kernel`):
  - comparer regulierement les obligations implementees avec les ingredients
    locaux explicites de la reduction:
    - `product_step_wf`
    - `product_step_has_live_source`
    - `product_step_is_bad_target`
  - lorsqu'un `__bad_code` bien forme passe au vert, verifier en priorite si
    l'encodage Why oublie:
    - la coherence structurelle du pas selectionne;
    - le fait que la propagation n'est pertinente que depuis une source live;
    - la clause locale interdisant une cible garantie mauvaise sous hypothese
      encore vivante.

- Priorite de correction pour `without_calls`:
  - preferer d'abord retablir la presence des clauses kernel pertinentes,
    meme si cela augmente temporairement le cout solver;
  - ne pas "gagner du vert" en re-eliminant des pas explicites si cela
    supprime la clause `safety` ou la propagation necessaire a la reduction.

- Traitement des regressions apres retablissement des clauses kernel:
  - distinguer strictement:
    - faux vert de correction (mauvaise clause manquante);
    - faux rouge de performance solver (clause presente mais trop couteuse a
      `5s`);
  - pour un `ok` qui casse apres renforcement kernel:
    - verifier d'abord que `--dump-obligations-map` montre bien une couverture
      explicite non vide;
    - puis rejouer le cas avec un timeout plus large pour savoir si le
      probleme est semantique ou seulement budgetaire.
  - ne pas essayer de gagner du temps solver en supprimant des pas/clauses au
    niveau du produit tant que cela risque de refaire tomber `coverage` a
    `empty` sur un contre-exemple minimal de correction.
  - lorsqu'un test d'overlap local est utilise pour ecremer des branches:
    - verifier explicitement qu'il detecte bien:
      - plusieurs valeurs positives incompatibles pour une meme variable;
      - un meme litteral a la fois positif et negatif;
    - preferer corriger ce predicate a la source dans l'exploration produit
      plutot que post-filtrer plus tard les clauses kernel.

- Optimisation backend Why autorisee apres retablissement de la correction:
  - si le produit explicite et les clauses IR sont corrects mais qu'un `ok`
    reste trop couteux a `5s`, preferer une contraction backend
    implication-preservante des clauses kernel:
    - fusion des clauses de propagation d'un meme pas en un resume
      conjonctif unique;
    - elimination backend des clauses de propagation d'un pas `bad_G` si la
      clause `safety` du meme pas est deja emise;
    - deduplication exacte des hypotheses / conclusions Why avant emission.
  - ne jamais faire cette contraction dans l'IR si cela brouille
    l'alignement avec la formalisation Rocq; la reduction de reference doit
    rester lisible et comparee a `kairos-kernel`, l'optimisation ne devant
    exister qu'au niveau emission Why.

- Priorite immediate `without_calls`:
  - considerer `armed_delay` comme cas directeur de performance solver;
  - une fois les autres `ok` repasses verts a `5s`, concentrer le diagnostic
    sur le reliquat `Track -> Track` de `armed_delay`;
  - n'ouvrir a nouveau le chantier `with_calls` qu'apres stabilisation de ce
    socle.

- Mise a jour de la suite immediate:
  - `armed_delay` ne doit plus etre traite comme blocage principal tant qu'il
    retombe vert en replay cible a `5s`;
  - la prochaine validation pertinente devient:
    - rerun complet `without_calls`;
    - verification que les `ok` restent verts a `5s`;
    - verification que les `ko` actifs restent `invalid` ou `timeout`, jamais
      `valid`;
    - seulement ensuite reprise du chantier `with_calls`.

- Ajustement apres relance reelle de campagne:
  - ne pas conclure a la stabilite d'un cas seulement sur des replays isoles;
  - verifier aussi son comportement dans la campagne sequentielle complete,
    car la pression solver peut differer;
  - tant que `armed_delay` ou `armed_fault_monitor` retombent rouges dans
    `without_calls_ok_report.tsv.tmp`, considerer `without_calls` comme
    encore instable.

- Regle de validation outillee:
  - toute campagne `ok/ko` doit maintenant etre lancee avec:
    - un timeout par obligation;
    - un timeout global par fichier;
  - si un fichier depasse le budget global, le classer explicitement
    `TIMEOUT` plutot que laisser la campagne se bloquer.

- Priorite immediate actualisee pour `without_calls`:
  - traiter comme cas directeurs:
    - `armed_delay`
    - `armed_fault_monitor`
    - `credit_balance_monitor`
  - objectifs:
    - faire tomber `armed_delay` de `FAILED 1` a `OK`;
    - faire tomber `armed_fault_monitor` et `credit_balance_monitor` de
      `TIMEOUT file_timeout_60s` a `OK` ou au minimum a un echec borne et
      localise qui se laisse diagnostiquer.

- Apres simplification booléenne backend:
  - ne plus investir d'abord dans des simplifications globales
    `true/false/and/or/implies`, car le gain principal est deja capture;
  - concentrer la suite sur la structure des obligations des cas directeurs:
    - factorisation eventuelle des clauses kernel par famille de source;
    - reduction du nombre de pas explicites non utiles cote Why, uniquement si
      cela n'affaiblit pas l'IR kernel aligne Rocq;
    - ou decoupage des VCs monolithiques `step'vc` en sous-obligations plus
      locales si Why3 le permet proprement.

- Mise a jour methodologique 2026-03-12:
  - le decoupage `step -> step_from_<state>` doit etre soutenu par un
    rattachement explicite des contrats a leur etat source;
  - la bonne technique n'est pas une simplification de domaine, mais une
    propagation de metadonnees structurelles depuis l'IR kernel / les clauses
    compilees jusqu'a l'emission Why;
  - chaque helper doit au minimum assumer:
    - son etat programme source `vars.st = <State>`;
  - en revanche, l'ajout automatique d'une coherence forte
    `vars.__aut_state = <Aut>` deduite du produit a ete teste puis rejete,
    car il aggrave `armed_delay` (`FAILED 2` -> `FAILED 5`) dans l'etat
    courant du backend;
  - priorite immediate:
    - diagnostiquer les `FAILED 2` restants sur `armed_delay`
      (`step_from_track'vc`);
    - ne revenir a `armed_fault_monitor` et `credit_balance_monitor`
      qu'apres avoir transforme ce cas en `OK` ou en echec pleinement
      explique.

- Affinage 2026-03-12:
  - une tentative de reassertion automatique des invariants de branche apres
    les affectations preservees a ete branchee dans `why_core`;
  - elle ne modifie pas encore le Why effectif de `armed_delay`;
  - la priorite immediate devient donc plus precise:
    - inspecter la representation `runtime_action_view` / `action_blocks`
      de la branche `Track`;
    - verifier a quel niveau exact inserer les reassertions pour qu'elles
      apparaissent reellement dans le corps Why genere.

- Rectification methodologique 2026-03-12:
  - le vrai point de correction pour `armed_delay` n'est pas d'ajouter des
    assertions locales supplementaires, mais de respecter la temporalite du
    `TickCtx` Rocq lors de la compilation des gardes de pas du produit;
  - en particulier, les gardes moniteur doivent etre compilees avec une
    semantique mixte:
    - sorties courantes du tick;
    - memoire / `pre_k` de source;
  - ce principe est backend-agnostic dans son contenu semantique, meme si la
    correction immediate a ete implementee dans le backend Why.

- Priorite immediate mise a jour:
  - expliquer et corriger l'ecart entre:
    - le replay direct `--dump-proof-traces-json ...` qui donne `[]`
      sur `armed_delay`;
    - et `scripts/validate_ok_ko.sh ... single_ok` qui le classe encore
      `FAILED 1`;
  - seulement apres, reprendre `armed_fault_monitor` et
    `credit_balance_monitor`.

- Mise en conformite complementaire:
  - la temporalite mixte necessaire a certaines clauses kernel ne doit pas
    rester un traitement special cache dans `why_contracts`;
  - elle doit etre portee par l'IR lui-meme;
  - un temps de clause explicite `StepTickContext` a donc ete introduit pour
    encoder les faits lus sur le `TickCtx` du pas;
  - le backend Why n'a plus qu'a respecter cette temporalite explicite.

## Regle de depot explicite

- Un [AGENTS.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/AGENTS.md) a ete ajoute a la racine du depot Kairos.
- Cette regle devient une contrainte d'architecture permanente:
  - `__aut_state` peut rester une vraie variable d'etat Kairos;
  - les faits du tick courant et des decalages temporels ne doivent pas etre
    prouves par reexecution de gardes moniteur dans Why3;
  - ils doivent etre exprimes directement sur les variables Kairos courantes
    et les variables decalees.

- Consequence pratique pour la suite:
  - toute correction future sur le backend Why / IR produit / resumes de `call`
    doit d'abord etre evaluee contre cette regle;
  - si une solution repose sur des gardes d'automate pour etablir un fait sur
    le tick courant ou `pre_k`, elle doit etre rejetee.

- Le `AGENTS.md` a aussi ete enrichi pour rendre la discipline plus operationnelle:
  - les faits necessaires a la preuve doivent exister d'abord dans l'IR /
    clauses kernel, pas seulement dans l'emetteur Why;
  - toute formule doit rendre son point temporel explicite;
  - un desaccord replay direct / validateur est un bug a traiter, pas du bruit;
  - les `bad_code` doivent etre classes explicitement si un faux vert subsiste;
  - les `call` modulaires doivent rester fondes sur `.kobj`;
  - chaque changement backend / produit doit etre accompagne d'un
    avant/apres minimal.

## Verrou technique restant sur les appels modulaires

- Diagnostic courant:
  - le backend Why3 reste bloque sur la representation des resultats de `call`
    dans les obligations locales du caller;
  - apres elimination des projections de records importes, il reste un
    probleme de liaison/portee autour des symboles intermediaires
    `__call_next_*`.

- Direction retenue pour la suite:
  - conserver l'ABI logique explicite pre/post/sorties/entrees introduite
    via les resumes `.kobj`;
  - reprendre le plan `ActionCall` jusqu'a obtenir un `any` Why local dont
    toutes les variables de resultat sont liees dans les `ensures`;
  - une fois ce point stable, rebrancher la campagne finale complete:
    - build `cli`
    - build `lsp`
    - build `ide`
    - `ok`
    - `ko`
    - puis `legacy`.
## Mise a jour 2026-03-12 - Discipline moniteur / temporalite

### Regle durcie
- `__aut_state` est autorise comme etat Kairos execute.
- les faits sur le tick courant, `prev`, `pre_k`, source/cible ne doivent pas etre derives de `assume_guard` / `guarantee_guard` dans le backend Why.

### Consequence methodologique
- les projections de gardes moniteur sur les contrats de transition ne doivent plus etre utilisees dans le pipeline actif ;
- les obligations doivent provenir des clauses kernel explicites ou de relations IR explicites ;
- tout correctif futur doit d'abord verifier qu'il n'introduit pas a nouveau une semantique de moniteur hors simulation de `__aut_state`.

### Etat apres mise en conformite
- le pipeline actif n'injecte plus les projections `assume/guarantee` basees sur les gardes moniteur ;
- le prochain travail doit porter sur la divergence entre replay direct et validateur, pas sur la semantique moniteur elle-meme.

### Verification minimale attendue apres chaque changement backend
- echantillon `ok` en `single_ok` ;
- echantillon `ko` en `single_ko` ;
- si les `ko` restent non verts mais que plusieurs `ok` tombent en `FAILED`, traiter d'abord le chemin validateur / l'orchestration avant de conclure a une regression semantique.

### Precaution supplementaire
- ne pas promouvoir directement une clause de securite post-etat en precondition de helper sans justification explicite cote IR ;
- si un cas `ok` exige un lien du type `local = pre_k(input)`, le produire comme fait source-etat explicite, pas comme consequence ad hoc du backend Why.

### Retour d'experience 2026-03-12
- un resume source "negation des cas `bad_guarantee`" est une bonne direction architecturale ;
- mais, sur les cas `Hold` actuels, ce resume ne suffit pas a lui seul a faire tomber les VCs ;
- avant d'aller plus loin, il faut identifier plus precisement quel fragment du `step_from_hold'vc` reste non prouve apres introduction de ce resume.

### Resultat du diagnostic de tuyauterie
- la perte du resume source intervient avant l'emission Why utile des helpers ;
- il faut maintenant auditer le calcul `bad_cases` / `src_states` dans `why_contracts` ou, mieux, faire remonter ce resume sous forme de clause IR deja materialisee et testable avant backend ;
- eviter les injections directes dans `emit.ml`, qui ont degrade les cas directeurs.

## Mise a jour 2026-03-12 - Priorite immediate sur l'IR des resumes source

### Ce qui est maintenant clair
- les resumes source des helpers ne doivent pas etre derives du moniteur ;
- `OriginSourceProductSummary` est maintenant bien materialise dans l'IR exporte et dans les `.kobj` ;
- la prochaine transition propre reste de faire consommer directement ces clauses IR par `why_contracts`, puis de retirer le fallback `product_steps`.

### Priorite immediate
1. relancer un echantillon plus large `without_calls/ok` et `without_calls/ko` maintenant que les cas directeurs repassent en `single_ok` ;
2. ensuite relancer la suite `without_calls` complete ;
3. seulement apres, reprendre `with_calls`.

### Regle de conduite
- ne pas empiler de nouveaux hints Why tant que l'IR ne porte pas lui-meme la clause source attendue ;
- maintenant que `OriginSourceProductSummary` est rebranche jusqu'au Why, reduire progressivement le fallback `product_steps` une fois le residu `step_from_hold'vc` traite ;
- verifier apres chaque tentative :
  - presence et contenu utile de `OriginSourceProductSummary` dans le `.kobj`,
  - forme des `requires` de `step_from_<state>`,
  - statut cible `single_ok`.

### Etat courant
- `OriginSourceProductSummary` est present dans les `.kobj` ;
- `why_contracts` le consomme directement ;
- les cas directeurs `gated_echo_bundle`, `sticky_bypass_echo`, `sticky_ack_plus`, `armed_delay` sont revenus au vert en `single_ok`.

## Mise a jour 2026-03-12 - Suite immediate apres le retablissement partiel

### Ce qui est maintenant acte
- en mode kernel, les hypotheses globales utilisateur (`transition_requires_pre`) doivent rester actives ;
- les hypotheses d'origine `Compatibility` issues du moniteur ne doivent plus etre reutilisees comme preconditions Why quand le kernel produit deja les clauses semantiques ;
- les tentatives d'aide solver locales doivent rester minimales et etre retirees immediatement si elles degradent un cas deja vert.

### Priorite suivante
1. re-isoler proprement `toggle.kairos` sur l'etat courant pour confirmer s'il s'agit d'une regression stable ou d'un effet de campagne ;
2. traiter `reset_zero_sink.kairos` comme dernier cas directeur `without_calls/ok` encore clairement rouge ;
3. seulement apres ces deux points, relancer `without_calls` complet et reevaluer l'etat global des `ok/ko`.

### Ligne directrice pour `reset_zero_sink`
- ne pas reintroduire de compatibilite moniteur ad hoc ;
- ne pas bricoler Why avec des assertions post-affectation generales si elles ne montrent pas un gain mesure ;
- travailler soit :
  - sur la forme IR des resumes source `OriginSourceProductSummary` pour l'etat `Zero`,
  - soit sur la structuration locale des VCs `step_from_zero`,
  mais toujours a partir de faits explicites de l'IR et non d'une reinterpretation du moniteur.

### Resultat du diagnostic comparatif approfondi
- `toggle` :
  - les resumes source IR sont simples et corrects ;
  - le residu vient plutot d'une fuite `Compatibility` encore visible dans `step_from_run`.
- `reset_zero_sink` :
  - les resumes source IR existent, mais sont encore trop indirects pour `Zero` ;
  - le helper `step_from_zero` montre lui aussi une fuite `Compatibility`.

### Consequence methodologique immediate
1. identifier la source precise de `origin:compatibility` encore presente dans `step_from_run` / `step_from_zero` malgre les filtrages deja ajoutes ;
2. l'eliminer proprement si elle n'est pas alignee avec le mode kernel ;
3. seulement ensuite reevaluer si `reset_zero_sink` demande un raffinement IR de `OriginSourceProductSummary`.

### Etat apres suppression de cette fuite
- la fuite `Compatibility` a bien ete retiree de `step_from_run` sur `toggle` ;
- `require_delay_bool` reste vert et `armed_delay__bad_code` reste invalide ;
- mais `toggle` et `reset_zero_sink` restent chacun avec un residu `FAILED 1`.

### Prochaine etape maintenant legitimement justifiee
- reprendre le residu logique local de ces deux cas comme un vrai probleme kernel / VC :
  - pour `toggle`, analyser le `step_from_run'vc` avec seulement les resumes source `Run/Aut0 -> y=0` et `Run/Aut1 -> y=1` ;
  - pour `reset_zero_sink`, analyser si le resume source `Zero` doit etre reformule en IR de facon plus directe.

## Ajout 2026-03-13 - Documentation structurante des obligations IR

### Objectif
- disposer d'un document de reference court mais exact sur :
  - les obligations generees au niveau IR ;
  - leur role ;
  - leur forme temporelle ;
  - le chemin actif `generated_clauses` -> `relational_generated_clauses` -> Why.

### Methode
1. partir d'un cas simple et stable (`delay_int`) ;
2. extraire les artefacts reels a chaque etape ;
3. decrire seulement les niveaux utiles pour la preuve ;
4. distinguer explicitement :
   - niveaux de construction ;
   - niveaux cibles de preuve ;
5. noter les dettes residuelles sans les masquer.

### Livrable
- `docs/ir_obligations_etude_delay_int_2026-03-13.md`
- PDF correspondant.

### Point methodologique ajoute
- pour toute refonte du pipeline de preuve, maintenir un cas file minimal documente de bout en bout ;
- le cas `delay_int` sert maintenant de reference minimale pour :
  - le produit explicite ;
  - les clauses brutes ;
  - les clauses relationnelles ;
  - l'abaissement des `pre_k` ;
  - la lecture du Why genere.

## Ajout 2026-03-13 - Support de clarification

### Objectif
- maintenir un fichier `Resume.md` a la racine pour consigner, au fil des
  echanges, les points a clarifier puis stabiliser sur l'architecture et la
  semantique de Kairos.

### Methode
1. ne mettre dans `Resume.md` que des points explicitement demandes ou
   tranches pendant la discussion ;
2. garder ce fichier court, stable et lisible ;
3. reserver le `cahier_de_laboratoire` au suivi des tentatives et
   `objectif_methodologie` au cadre de travail.
4. lorsqu'un point semantique est ajoute, noter aussi explicitement ses
   hypotheses et la nuance inverse eventuelle.
