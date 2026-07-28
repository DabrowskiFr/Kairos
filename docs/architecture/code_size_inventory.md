# Inventaire de la taille du code Kairos

- Date de mesure : 2026-07-27
- Branche : `architecture-simplification`
- Commit : `3ece7c15`

Les tableaux globaux de cet inventaire décrivent l'état initial à ce commit.
La section « Évolution du backend Why3 » conserve cette référence et mesure
séparément l'état consolidé de la branche.

## Périmètre et méthode

Le comptage principal porte sur tous les fichiers suivis par Git en `.ml` et
`.mli`. Les lignes sont des lignes physiques : les commentaires et lignes
vides sont inclus. Les fichiers produits sous `_build` et les modules générés
par Dune ne sont pas comptés.

Commandes de base :

```sh
git ls-files -z '*.ml' '*.mli' | xargs -0 wc -l
git ls-files -z '*.ml' | xargs -0 wc -l
git ls-files -z '*.mli' | xargs -0 wc -l
```

L'affectation aux bibliothèques est réconciliée avec les stanzas `(modules
...)` des fichiers `dune` et avec :

```sh
dune describe workspace --lang 0.1 --format sexp
```

La grammaire Menhir, les scripts, l'extension VSCode, le corpus `.kairos` et
la documentation sont comptés séparément.

## Synthèse

| Nature | Fichiers | LOC |
| --- | ---: | ---: |
| Implémentations `.ml` | 314 | 34 434 |
| Interfaces `.mli` | 282 | 11 784 |
| **Total OCaml** | **596** | **46 218** |

Les interfaces représentent 25,5 % des lignes OCaml. Le total se réconcilie
ainsi :

```text
39 762  bibliothèques Dune
 5 173  exécutables
 1 283  tests
------
46 218  total .ml/.mli
```

Hors tests, le code OCaml de production représente 44 935 lignes dans 585
fichiers.

## Répartition fonctionnelle

Les onze modules de test sont isolés de leurs répertoires physiques dans ce
tableau.

| Bloc | Fichiers | LOC `.ml` | LOC `.mli` | Total LOC | Part |
| --- | ---: | ---: | ---: | ---: | ---: |
| Domaine scientifique | 98 | 6 663 | 2 697 | **9 360** | 20,3 % |
| Backend Why3 interne à Kairos | 116 | 5 727 | 2 474 | **8 201** | 17,7 % |
| LSP, bibliothèques et exécutable | 173 | 3 658 | 2 273 | **5 931** | 12,8 % |
| Runtime d'orchestration | 57 | 4 405 | 1 154 | **5 559** | 12,0 % |
| Frontend du langage Kairos | 40 | 4 176 | 657 | **4 833** | 10,5 % |
| Contrats et adaptateurs externes | 42 | 3 211 | 1 520 | **4 731** | 10,2 % |
| Moteur et API | 14 | 1 952 | 185 | **2 137** | 4,6 % |
| Rendus texte et graphes | 16 | 1 429 | 297 | **1 726** | 3,7 % |
| CLI | 9 | 1 083 | 246 | **1 329** | 2,9 % |
| Tests OCaml | 11 | 1 283 | 0 | **1 283** | 2,8 % |
| Générateur C | 20 | 847 | 281 | **1 128** | 2,4 % |
| **Total** | **596** | **34 434** | **11 784** | **46 218** | **100 %** |

## Répartition par paquet

Les tests sont exclus de cette vue.

| Paquet opam | Bibliothèques / exécutables | Fichiers OCaml | LOC |
| --- | ---: | ---: | ---: |
| `kairos-engine-runtime` | 14 bibliothèques | 223 | **18 751** |
| `kairos` | 4 bibliothèques | 138 | **14 193** |
| `kairos-lsp` | 2 bibliothèques + 1 exécutable | 173 | **5 931** |
| `kairos-why3-adapter` | 1 bibliothèque | 24 | **2 524** |
| `kairos-cli` | 1 exécutable | 9 | **1 329** |
| `kairos-telemetry` | 1 bibliothèque | 6 | **1 108** |
| `kairos-spot-adapter` | 1 bibliothèque | 6 | **613** |
| `kairos-proof-contract` | 1 bibliothèque | 4 | **302** |
| `kairos-automata-contract` | 1 bibliothèque | 2 | **184** |
| **Total production** | **25 bibliothèques + 2 exécutables** | **585** | **44 935** |

`kairos-engine-runtime` concentre 41,7 % du code de production. Sa taille vient
principalement du backend Why et des runtimes, et non de la façade
`Kairos_engine.Api`.

## Les 25 bibliothèques Dune

Les exécutables et les tests sont exclus.

| Bibliothèque | Fichiers `.ml` / LOC | Fichiers `.mli` / LOC | Total LOC |
| --- | ---: | ---: | ---: |
| `kairos_domain_core` | 16 / 1 741 | 16 / 881 | **2 622** |
| `kairos_domain_verification` | 23 / 3 345 | 23 / 1 146 | **4 491** |
| `kairos_domain_proof_export` | 10 / 1 577 | 10 / 670 | **2 247** |
| `kairos_input_lang` | 24 / 4 176 | 16 / 657 | **4 833** |
| `kairos_lsp_protocol` | 1 / 444 | 1 / 517 | **961** |
| `kairos_lsp_app` | 8 / 882 | 8 / 244 | **1 126** |
| `kairos_artifact_graph_render` | 6 / 969 | 6 / 238 | **1 207** |
| `kairos_artifact_text_render` | 2 / 460 | 2 / 59 | **519** |
| `kairos_c_codegen` | 10 / 847 | 10 / 281 | **1 128** |
| `kairos_why3_expr` | 6 / 446 | 6 / 307 | **753** |
| `kairos_why3_runtime_view` | 5 / 727 | 5 / 288 | **1 015** |
| `kairos_why3_contracts` | 1 / 183 | 1 / 67 | **250** |
| `kairos_why3_compile` | 44 / 3 997 | 44 / 1 716 | **5 713** |
| `kairos_why3_render` | 1 / 279 | 1 / 37 | **316** |
| `kairos_why3` | 1 / 95 | 1 / 59 | **154** |
| `kairos_runtime_core` | 9 / 1 366 | 5 / 488 | **1 854** |
| `kairos_runtime_automata` | 3 / 415 | 3 / 117 | **532** |
| `kairos_runtime_proof` | 7 / 804 | 7 / 238 | **1 042** |
| `kairos_runtime_diagnostics` | 12 / 1 820 | 11 / 311 | **2 131** |
| `kairos_engine` | 10 / 1 952 | 4 / 185 | **2 137** |
| `kairos_automata_contract` | 1 / 120 | 1 / 64 | **184** |
| `kairos_proof_contract` | 2 / 166 | 2 / 136 | **302** |
| `kairos_spot_adapter` | 3 / 486 | 3 / 127 | **613** |
| `kairos_external_timing` | 3 / 565 | 3 / 543 | **1 108** |
| `kairos_external_why3` | 12 / 1 874 | 12 / 650 | **2 524** |
| **Total** | **220 / 29 736** | **201 / 10 026** | **39 762** |

## Détail des blocs dominants

### Domaine scientifique

| Sous-bloc | LOC |
| --- | ---: |
| `lib/domain/core` | 2 622 |
| `lib/domain/verification` | 4 491 |
| `lib/domain/proof_export` | 2 247 |
| **Total** | **9 360** |

### Runtime

| Bibliothèque | LOC |
| --- | ---: |
| `kairos_runtime_core` | 1 854 |
| `kairos_runtime_automata` | 532 |
| `kairos_runtime_proof` | 1 042 |
| `kairos_runtime_diagnostics` | 2 131 |
| **Total** | **5 559** |

### Backend Why3 interne

| Bibliothèque | LOC |
| --- | ---: |
| `kairos_why3_compile` | 5 713 |
| `kairos_why3_runtime_view` | 1 015 |
| `kairos_why3_expr` | 753 |
| `kairos_why3_render` | 316 |
| `kairos_why3_contracts` | 250 |
| `kairos_why3` | 154 |
| **Total** | **8 201** |

La chaîne de preuve élargie — backend Why3 interne, adaptateur Why3 externe,
runtime de preuve et contrat de preuve — représente 12 069 lignes.

### Évolution du backend Why3

Le comptage avant/après porte sur le même périmètre
`lib/adapters/out/provers/why3`, toujours en lignes physiques `.ml`/`.mli`.
L'état « avant » est celui du commit `3ece7c15`; l'état « après » est l'arbre
de travail consolidé de `architecture-simplification` au 2026-07-27.

| Mesure | Avant | Après | Écart |
| --- | ---: | ---: | ---: |
| Modules | 58 | 16 | **-42 (-72,41 %)** |
| Fichiers `.ml`/`.mli` | 116 | 32 | **-84 (-72,41 %)** |
| LOC implémentations `.ml` | 5 727 | 2 040 | **-3 687 (-64,38 %)** |
| LOC interfaces `.mli` | 2 474 | 634 | **-1 840 (-74,37 %)** |
| **Total LOC** | **8 201** | **2 674** | **-5 527 (-67,39 %)** |

La répartition entre les bibliothèques Why3 internes est désormais :

| Bibliothèque | Avant | Après | Écart |
| --- | ---: | ---: | ---: |
| `kairos_why3_compile` | 5 713 | 2 536 | -3 177 |
| `kairos_why3_runtime_view` | 1 015 | 0 | -1 015 |
| `kairos_why3_expr` | 753 | 0 | -753 |
| `kairos_why3_render` | 316 | 0 | -316 |
| `kairos_why3_contracts` | 250 | 0 | -250 |
| `kairos_why3` | 154 | 138 | -16 |
| **Total** | **8 201** | **2 674** | **-5 527** |

Cette baisse vient principalement de la fusion des façades et micro-modules
de compilation, puis de la suppression des optimisations à faible rendement.
Le backend conserve le groupage avec factorisation canonique des préconditions
communes, les prédicats compacts pour les contrats multi-clauses et un partage
ciblé des compositions propositionnelles répétées. La simplification FO
optionnelle, le slicing des corps et leur câblage public ont été supprimés.

La vue runtime Why3 a ensuite été supprimée. `Ir.node_ir`,
`Ir.transition`, `Core_syntax.stmt` et
`Step_contract_projection.step_contract` sont désormais consommés
directement. Les copies `port_view`, `runtime_action_view`,
`runtime_transition_view` et `runtime_product_transition_view` n'existent
plus.

`Why_pipeline` délègue directement à l'imprimante native de Why3. La
bibliothèque de rendu séparée a disparu avec le post-traitement purement
présentatif, son plumbing de labels et de spans.

La bibliothèque `kairos_why3_contracts` a également disparu.
`Why_compile_product_specs` compile directement les familles logiques de
`Step_contract_projection.step_contract`. La comparaison sur 44 programmes
confirme que les 132 artefacts `.why`, `.vc` et `.smt` restent identiques
octet pour octet.

Enfin, l'audit d'usage de `compile` a supprimé 15 fonctions mortes et retiré
des interfaces les fonctions strictement internes. Ce nettoyage enlève
261 lignes supplémentaires. Une comparaison ciblée de quatre programmes
couvrant contrats d'action, historique, tableaux et fenêtres temporelles
conserve 12 artefacts `.why`, `.vc` et `.smt` identiques.

La frontière Dune `kairos_why3_expr`, devenue sans consommateur autre que
`kairos_why3_compile`, a ensuite été absorbée par cette dernière. Le module
`Why_compile_expr` reste distinct, mais le backend Why3 interne ne comporte
plus que deux bibliothèques Dune : compilation et façade.

Les alias `proof_terms` et `grouped_terms`, ainsi que l'accesseur identité
associé, ont enfin été supprimés. La planification a ensuite quitté Why3 :
`Proof_plan.t`, dans le domaine de vérification, porte directement les
obligations individuelles ou groupées et leur factorisation.

L'audit sémantique des abstractions appelées a ensuite retiré la transition
dupliquée dans les entrées de groupe, un conteneur mono-champ, les records de
callbacks et de contexte sans invariant, les champs dérivables, le chemin de
module toujours fixé à `None`, ainsi que le module de pur câblage
`Why_compile_product_pipeline`. Les séquences d'expressions dupliquées ont été
factorisées dans l'utilitaire `Ptree` commun.

Le filtrage des paramètres inutilisés des helpers a au contraire été
conservé après mesure : sa suppression ne change ni les VC ni le SMT, mais
augmente le WhyML de 0,94 %, modifie 39 programmes sur 44 et provoque de
nombreux avertissements Why3 `unused variable`. Son implémentation ne
reparcourt toutefois plus les arbres `Ptree` produits. Les accès aux entrées
sont maintenant collectés pendant la traduction des expressions Kairos, puis
propagés explicitement aux bundles, aux termes groupés et aux helpers. Le
parcours générique des termes, spécifications et expressions Why3 disparaît.
Les 132 artefacts du corpus restent identiques octet pour octet.

Les clés textuelles partielles des termes Why3 ont ensuite été remplacées par
l'égalité structurelle de `Ptree.term` pour la déduplication, les bundles et
la factorisation. Le sérialiseur manuel, qui ramenait les constructeurs non
gérés à la même clé `"?"`, a disparu. Les 132 artefacts `.why`, `.vc` et
`.smt` du corpus valide restent identiques octet pour octet.

Les constructeurs d'identifiants, de termes, d'expressions, de `use` et de
spécification vide utilisent enfin `Why3.Ptree_helpers` au lieu de
reconstruire manuellement les mêmes nœuds.

### Audit fonctionnel ayant guidé la simplification

Cet audit distingue trois mesures qui ne doivent pas être confondues :

1. le **noyau dédié**, compté par fichiers dont la responsabilité entière est
   l'optimisation ;
2. la **surface de couplage**, comptée par modules mixtes touchés, mais qui
   contient aussi de la compilation indispensable et n'est donc pas un gain
   supprimable ;
3. l'**effet expérimental**, mesuré sur les 44 programmes de `tests/ok`.

#### Noyau dédié

| Mécanisme | Module | Avant | Après | Écart |
| --- | --- | ---: | ---: | ---: |
| Émission Why3 des formules partagées | `why_compile_formula_sharing` | 448 | 171 | -277 |
| Construction et réutilisation de bundles | `why_compile_bundles` | 315 | 119 | -196 |
| Construction et factorisation canonique des groupes | `why_compile_product_group_terms` | 418 | 161 | -257 |
| Partition et planification des groupes | `why_compile_product_groups` | 345 | 180 | -165 |
| **Total dédié** |  | **1 526** | **631** | **-895** |

Ces 631 lignes représentent désormais **28,22 %** des 2 236 lignes du
répertoire `compile` du backend Why3. Il
s'agit d'un minimum structurel exact, et non d'une estimation du gain d'une
suppression.

Le passage public des options supprimées a disparu. Le seul choix de forme
backend encore configurable est le groupage des pas produit.

#### Les bundles ne constituent pas une option homogène

Avant la simplification, `share_why3_facts = false` désactivait :

- les prédicats représentant les formules de contrat répétées ;
- les bundles de familles pré/post identiques.

Il ne désactive pas :

- le prédicat de précondition construit pour chaque helper individuel ;
- le bundle d'une postcondition individuelle contenant plusieurs termes.

Cette ambiguïté a été supprimée avec l'option. Les bundles restants ont une
responsabilité unique et toujours active : garder compacts les contrats
multi-clauses.

#### Mesure expérimentale sur le corpus valide

Chaque variante a été appliquée séparément aux 44 programmes. Les tailles
agrègent les artefacts complets du corpus. Les 44 programmes restent prouvés
avec Z3 et un timeout d'une seconde par but dans toutes les variantes.

| Variante | Modules WhyML | Buts | WhyML octets | VC octets | SMT octets |
| --- | ---: | ---: | ---: | ---: | ---: |
| Défaut | 812 | 442 | 996 781 | 5 286 878 | 2 999 840 |
| Sans partage | 532 | 442 | 1 387 076 | 5 256 957 | 2 658 185 |
| Sans simplification FO backend | 812 | 442 | 997 494 | 5 287 297 | 3 001 460 |
| Sans slicing des corps | 808 | 442 | 999 854 | 5 320 567 | 3 041 023 |
| Sans déduplication | 812 | 442 | 1 031 573 | 5 313 173 | 3 031 582 |
| Sans groupage | 1 146 | 579 | 984 837 | 6 659 181 | 3 727 574 |
| `--no-proof-optimizations` | 864 | 583 | 1 337 758 | 6 646 273 | 3 550 731 |

Effet relatif de chaque désactivation par rapport au défaut :

| Désactivation | WhyML | VC | SMT | Observation |
| --- | ---: | ---: | ---: | --- |
| Partage | +39,16 % | -0,57 % | **-11,39 %** | Réduit le source WhyML, mais augmente le SMT sur ce corpus |
| Simplification FO backend | +0,07 % | +0,01 % | +0,05 % | Effet négligeable |
| Slicing | +0,31 % | +0,64 % | +1,37 % | Gain faible |
| Déduplication | +3,49 % | +0,50 % | +1,06 % | Bon rapport simplicité/coût |
| Groupage | -1,20 % | **+25,96 %** | **+24,26 %** | Réduit réellement le nombre et la taille des obligations |
| Toutes les options publiques | +34,21 % | +25,71 % | +18,36 % | Conserve encore les bundles génériques |

Le nombre de buts montre que seule la désactivation du groupage modifie
fortement la répartition des obligations : 442 buts par défaut contre 579 sans
groupage. Les autres options conservent les 442 buts.

#### Suppression de la sélection de factorisation

Avant simplification, le sélecteur choisissait entre quatre formes sur les 83
groupes du corpus :

| Forme sélectionnée | Groupes |
| --- | ---: |
| Forme originale | 1 |
| Postconditions communes | 0 |
| Préconditions communes | 74 |
| Préconditions et postconditions communes | 8 |

Le coût estimé total de cette sélection était 172 733. Employer
systématiquement la forme `pre_common` donnait 173 379, soit seulement
**646 unités ou 0,37 % de plus** selon le propre modèle de coût du backend.
La forme `post_common` n'est jamais sélectionnée.

Le backend utilise maintenant exclusivement `pre_common`. La comparaison
effective avec l'ancien sélecteur donne :

| Artefact | Ancien sélecteur | `pre_common` fixe | Écart |
| --- | ---: | ---: | ---: |
| Buts | 442 | 442 | 0 |
| WhyML | 995 931 octets | 996 781 octets | +0,085 % |
| VC | 5 286 161 octets | 5 286 878 octets | +0,014 % |
| SMT | 2 999 047 octets | 2 999 840 octets | +0,026 % |

Seuls 6 programmes sur 44 changent textuellement. Les 44 restent prouvés avec
Z3 et un timeout d'une seconde par but.

#### Diagnostic associé au groupage

Le profil des quatre candidats, les raisons d'individualisation, les snapshots
`why3_product_group`, leur stockage et leurs champs CSV ont été supprimés. Le
backend Why3 perd 383 lignes sur cette tranche. Les structures de télémétrie
correspondantes ont également disparu du package de timing et de l'engine.
Il ne reste aucune référence aux anciens coûts, formes candidates ou raisons
d'individualisation dans le code de production.

#### Conclusion de simplification

Les mécanismes ne doivent pas être supprimés en bloc :

1. le groupage apporte le seul gain structurel majeur observé et est conservé ;
2. la factorisation canonique `pre_common` remplace désormais le choix
   dynamique entre quatre formes ;
3. le diagnostic détaillé des candidats a été supprimé ;
4. le partage de formules doit être réévalué séparément : il raccourcit le
   WhyML, mais augmente de 11,39 % le SMT du corpus ;
5. le slicing et l'option de simplification FO backend ont un impact faible ;
6. la déduplication a un coût d'implémentation faible et un effet modeste mais
   cohérent ;
7. les bundles doivent d'abord être séparés entre représentation contractuelle
   toujours active et partage optionnel avant qu'un gain supprimable puisse
   être mesuré proprement.

#### Résultat appliqué

La branche applique maintenant cette conclusion. La simplification FO
backend, le slicing et leurs options ont été supprimés. La déduplication
syntaxique locale reste une normalisation inconditionnelle de quelques
lignes. Le groupage et les bundles compacts restent. Le partage de formules
a été reconstruit sans option ni seuil numérique. `Contract_formula_index`
sélectionne dans le domaine, par égalité structurelle exacte, les compositions
propositionnelles répétées dans des contrats distincts.
`Why_compile_formula_sharing` ne contient plus l'inventaire ni la notion
d'équivalence : il matérialise l'index en modules Why3 isolés et importés
seulement par leurs consommateurs.

Mesure finale sur les mêmes 44 programmes :

| Variante | Modules WhyML | Buts | WhyML octets | VC octets | SMT octets |
| --- | ---: | ---: | ---: | ---: | ---: |
| Référence avant suppression | 812 | 442 | 996 781 | 5 286 878 | 2 999 840 |
| Backend simplifié | 528 | 442 | 1 391 774 | 5 291 045 | 2 695 410 |
| Accès direct à l'IR, sans coalescence cachée | 540 | 455 | 1 425 324 | 5 439 805 | 2 774 581 |
| Partage propositionnel structurel | 785 | 455 | 1 020 924 | 5 488 007 | 3 146 692 |

Le backend simplifié augmente le VC de **0,08 %**, réduit le SMT de
**10,15 %**, et conserve les 442 buts. Les 44 programmes sont prouvés avec Z3
et un timeout d'une seconde par but. Une traduction entièrement directe sans
bundles a aussi été testée : 8 314 862 octets de VC et 3 727 528 octets de
SMT. Cette dégradation (+57 % VC, +24 % SMT) justifie de conserver le petit
service de bundles ciblé.

Le partage propositionnel réduit le WhyML ordinaire de **28,37 %** par
rapport à l'accès direct à l'IR. Le VC augmente de **0,89 %** et le SMT de
**13,41 %** ; les 455 buts des 44 programmes restent tous prouvés.

Les grands exemples médicaux justifient le mécanisme :

| Exemple | WhyML sans partage | WhyML partagé | Temps sans partage | Temps partagé |
| --- | ---: | ---: | ---: | ---: |
| Light | 2 445 715 | 847 311 | 1,085 s (médiane) | 0,815 s (médiane) |
| Full | 160 660 176 | 25 798 389 | 94,7 s | 34,50 s |

Le full reste à 656/656 buts prouvés. Le gain est de **83,94 %** sur la
taille WhyML et de **63,57 %** sur le temps total observé.

La canonicalisation est désormais générique. `Formula_canonical` fournit la
clé structurelle et l'internement physique ; `Temporal_lower` mémoïse
l'abaissement par formule d'entrée et interne ses résultats ;
`Proof_plan` construit l'index contractuel consommable par tout backend.
`Contract_formula_index` emploie les clés structurelles uniquement pendant la
construction des classes, puis associe chaque `oid` d'occurrence indexée à sa
définition partagée. Les recherches du backend ne reparcourent donc plus les
formules. `Pipeline_build` calcule une seule fois les contrats sur chaque
partition, puis le plan par nœud source ; génération Why et attribution des
buts consomment exactement ce plan, sans reconstruire ni comparer les
formules.

Les mesures séparées confirment où se trouve désormais le coût. Sur light,
la passe physique terminale `formula_sharing_s` prend 0,4 ms et la
planification avec index `proof_planning_s` 14,7 ms en médiane sur cinq
exécutions ; la
génération Why prend 25,1 ms. Sur full, ces trois mesures valent
respectivement 47,1 ms, 758,7 ms et 667,4 ms. Le full reste à 656/656 buts
prouvés en 35,73 s. Le calcul d'identité et de réutilisation n'est donc plus
un travail du backend Why et sa dépense est visible comme passe générique.

La validation stratégique effectuée après l'indexation directe par `oid`
donne les résultats suivants :

| Corpus | Résultat | Temps total | Planification | Partage | Génération Why |
| --- | ---: | ---: | ---: | ---: | ---: |
| `tests/ok` | 44/44 | — | — | — | — |
| Médical light | 83/83 | 0,990 s | 18,5 ms | 0,55 ms | 22,8 ms |
| Médical full | 656/656 | 31,666 s | 805,4 ms | 42,6 ms | 545,8 ms |

Sur le full, la génération Why représente environ 1,7 % du temps total.
Ces mesures ne justifient pas l'ajout d'une nouvelle représentation
symbolique pré-Why3.

La coalescence cachée de l'ancienne vue runtime ne concernait que 14 contrats
sur 545 et deux programmes sur 44. Sa suppression augmente, par rapport au
backend simplifié précédent, le WhyML de 2,41 %, le VC de 2,81 % et le SMT de
2,94 %. Ce coût reste faible face à la suppression de 575 lignes
supplémentaires et à la restauration d'une traçabilité directe vers les
contrats projetés. Les 455 buts restent tous prouvés sous une seconde.

## Fragmentation physique

| Mesure | Valeur |
| --- | ---: |
| Taille moyenne d'un fichier | 77,5 lignes |
| Taille médiane | 43 lignes |
| Fichiers de 25 lignes ou moins | 163 |
| Fichiers de 50 lignes ou moins | 339 |
| Fichiers de 100 lignes ou moins | 457 |
| Fichiers de plus de 250 lignes | 39 |
| Fichiers de plus de 400 lignes | 6 |

Deux concentrations expliquent une grande partie du nombre de fichiers :

- le LSP contient 5 931 lignes de production dans 173 fichiers ;
- `kairos_why3_compile` contient 5 713 lignes dans 88 fichiers.

La taille du dépôt vient donc à la fois de sa portée fonctionnelle et d'un
morcellement important en petits modules et interfaces.

## Éléments hors comptage OCaml

| Élément suivi par Git | LOC |
| --- | ---: |
| Grammaire Menhir `kx_parser.mly` | 1 071 |
| Scripts Python et shell | 3 386 |
| Extension VSCode TypeScript | 3 239 |
| Corpus de programmes `.kairos` | 4 092 |
| Documentation Markdown et odoc | 6 657 |
| Modèles et sources de graphes d'architecture | 4 971 |

Les SVG générés ne sont pas inclus dans ces lignes.
