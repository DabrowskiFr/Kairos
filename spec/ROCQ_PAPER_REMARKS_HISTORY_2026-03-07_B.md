# Remarques de relecture pour `spec/rocq_oracle_model.tex`

Ce fichier sert de tampon editorial courant.

Principe:
- les nouvelles remarques utilisateur sont d'abord consignees ici;
- lorsqu'un lot de remarques a ete traite dans le papier, il est deplace vers un
  fichier d'historique date;
- ce fichier ne contient donc que les remarques encore ouvertes.

Historique disponible:
- `spec/ROCQ_PAPER_REMARKS_HISTORY_2026-03-07.md`

## Remarques en attente

## Remarque 2026-03-07-1

Texte utilisateur:
- `il faudrait mieux justifier mathématiquement "Équation coinductive de sémantique"`

Interpretation:
- la proposition actuelle sur l'existence et l'unicite du flux coinductif est
  trop rapide au regard du niveau de rigueur vise par le papier;
- il faut soit donner une justification mathematique minimale du copoint fixe,
  soit reformuler plus prudemment ce passage.

Changements a faire:
- expliciter l'espace sur lequel porte l'operateur coinductif;
- justifier pourquoi l'equation definie est gardee;
- soit esquisser un argument d'existence/unicite,
  soit reformuler en definition coinductive plutot qu'en proposition trop forte;
- relier clairement cette justification a la presentation point par point qui
  suit.

## Remarque 2026-03-07-2

Texte utilisateur:
- `(su(0),mu(0)) = (s0,m0), il faut expliquer avant dans le papier les notations (application su(0), s0)`

Interpretation:
- certaines notations de base sur les suites d'etats et les etats initiaux sont
  utilisees avant d'avoir ete introduites explicitement;
- il faut annoncer clairement la convention de nommage et la lecture de ces
  symboles avant la premiere equation de semantique.

Changements a faire:
- introduire avant les equations les notations
  `s_u : Nat -> S`, `m_u : Nat -> M`, `o_u : Nat -> O`;
- rappeler que `s_0` et `m_0` designent les conditions initiales du programme,
  tandis que `s_u(k)` et `m_u(k)` designent les composantes de l'execution
  induite par l'entree `u`;
- harmoniser la typographie entre indices et applications pour eviter
  l'ambiguite.

## Remarque 2026-03-07-3

Texte utilisateur:
- `Il faut privilégier la notation -> pour step`

Interpretation:
- la notation de transition flechee doit devenir la notation principale du
  papier pour les pas de programme, et idealement pour les pas du produit quand
  cela reste lisible;
- les ecritures tuplees doivent rester auxiliaires et non centrales.

Changements a faire:
- reutiliser prioritairement la notation
  `((s,m),i) -> ((s',m'),o)` ou sa variante etiquetee;
- reduire les usages de la forme
  `step_P(s,m,i) = (t,s',m',o)` au strict necessaire;
- verifier la coherence de cette convention dans:
  - la semantique de flux,
  - les exemples,
  - la definition du produit,
  - la section sur les pas dangereux.

## Remarque 2026-03-07-4

Texte utilisateur:
- `Run(m) ⇒m= prev(x) : la on se prend un prev(x) sans comprendre pourquoi, comment ces prédicats sont interprétés et sur quel domaine. Il faut également dès le début expliquer la notion d'automate de sureté et la notion de reconnaissance associée`

Interpretation:
- le papier utilise trop tôt des formules avec passe (`prev(x)`) sans avoir
  encore défini:
  - le domaine d'interprétation de ces prédicats,
  - la sémantique de `prev/pre_k`,
  - ni même la notion générale d'automate de sûreté et de reconnaissance;
- il faut donc remonter ces définitions fondamentales plus tôt dans le texte.

Changements a faire:
- introduire plus en amont une section de base sur:
  - automates de sûreté,
  - run sur mot infini,
  - condition de reconnaissance `avoid bad`;
- définir ensuite le domaine sémantique des prédicats locaux:
  - contexte de tick,
  - trace,
  - interprétation de `prev(x)` et plus généralement `pre_k`;
- ne présenter l'exemple `Run(m) => m = prev(x)` qu'après cette mise en place;
- expliciter pourquoi une formule de ce type est bien une formule sur contexte
  de trace et non une formule sur mémoire instantanée seule.

## Remarque 2026-03-07-5

Texte utilisateur:
- `je voudrais que le prédicat interpréte les variables qui ne sont pas sous un prev comme la valeur courante de la variable de la mémoire, il faut donc définir de manière abstraite l'interprétation du prédicat et donc des variables dans la mémoire. L'utilisateur écrit simplement les variables sous réserves qu'elles soient définies dans le domaine de la mémoire. Tout ça doit être défini très précisément et rigoureusement.`

Interpretation:
- le papier doit donner une vraie sémantique des formules utilisateur, pas
  seulement des exemples informels;
- une variable libre non sous opérateur de passé doit être interprétée comme la
  valeur courante de cette variable dans la mémoire/configuration courante;
- les opérateurs `prev`/`pre_k` doivent ensuite être définis à partir de la
  trace d'exécution, sans changer cette règle de base.

Changements a faire:
- introduire un domaine abstrait des noms de variables mémoire et une fonction
  d'interprétation de la mémoire, par exemple
  `[[x]]_ctx = val_mem(ctx,x)` pour les variables courantes;
- définir rigoureusement la condition de bonne formation:
  une variable n'est autorisée dans une formule que si elle appartient au
  domaine mémoire/entrée/sortie prévu par la spécification;
- définir la sémantique des termes et prédicats par interprétation dans un
  contexte de tick:
  - variable courante,
  - variable sous `prev`,
  - variable sous `pre_k`,
  - connecteurs booléens;
- distinguer explicitement:
  - lecture courante dans la mémoire/configuration au tick `k`,
  - lecture historique via la trace aux ticks précédents;
- remplacer les formulations trop concrètes ou ambiguës du type `m = prev(x)`
  par une sémantique d'évaluation abstraite des variables.

## Remarque 2026-03-07-6

Texte utilisateur:
- `dans le papier il faut faire pareil, des propriétés quelconques sur l'historique. Et on peut utiliser prev en précisant que c'est un cas particulier et comment il s'interpréte dans ce cadre abstrait`

Interpretation:
- le papier doit s'aligner sur le niveau sémantique actuel de la formalisation
  Rocq pour les invariants de nœud:
  ils sont des propriétés arbitraires sur le contexte de trace, pas une classe
  spéciale limitée à quelques schémas de formules;
- `prev` doit être introduit ensuite comme un opérateur particulier utile en
  pratique, et non comme la définition même des invariants.

Changements a faire:
- présenter les invariants utilisateur comme des prédicats quelconques sur le
  contexte de trace / l'historique;
- ne plus donner l'impression que les invariants sont essentiellement de la
  forme `x = prev(y)`;
- introduire `prev` seulement après la définition abstraite générale, en
  précisant:
  - que c'est un cas particulier,
  - comment il s'interprète sur la trace,
  - et comment il se relie à l'encodage fini de l'implémentation;
- relier explicitement cette présentation à la formalisation Rocq
  `node_inv : StepCtx -> Prop`.

## Remarque 2026-03-07-7

Texte utilisateur:
- `dans le papier, Inv ne doit pas être une famille de propriétés distinctes si l'on peut les agréger par conjonction`

Interpretation:
- au niveau sémantique du papier, il est inutile d'introduire une collection
  d'invariants distincts par nœud si leur conjonction suffit à représenter la
  propriété globale voulue;
- il vaut mieux présenter un invariant agrégé unique par état, et réserver la
  multiplicité des obligations au niveau de l'implémentation/backend si besoin.

Changements a faire:
- remplacer la présentation actuelle de type
  `Inv : S -> P(TickCtx -> B)` par une forme plus simple:
  - `Inv : S -> TickCtx -> B`, ou
  - extensionnellement `Inv : S -> P(TickCtx)`;
- expliquer qu'un ensemble fini d'invariants utilisateur peut être agrégé par
  conjonction dans cet invariant unique;
- éviter d'introduire une collection de propriétés distinctes au niveau du
  modèle mathématique si elle n'apporte rien à la compréhension;
- garder, si nécessaire, la multiplicité des obligations pour la provenance ou
  le backend, mais pas dans la définition sémantique de base.

## Remarque 2026-03-07-8

Texte utilisateur:
- `dans "États et pas du produit" la mémoire ne doit pas faire partie de l'état du produit, sinon on n'a plus un automate fini; ce n'est d'ailleurs pas ce que fait Rocq`

Interpretation:
- le papier raconte actuellement une mauvaise histoire sur le produit:
  il suggère que la mémoire est incluse dans l'état du produit, alors que la
  formalisation Rocq et l'implémentation OCaml la placent au niveau du pas
  concret / du contexte local;
- cette confusion brouille la distinction essentielle entre:
  - la partie finie du produit,
  - et les données locales du tick utilisées pour évaluer le pas.

Changements a faire:
- corriger la section `États et pas du produit` pour que l'état du produit soit
  explicitement de la forme `S × Q_A × Q_G`;
- expliquer que la mémoire, l'entrée et la sortie interviennent dans les pas
  concrets et les contextes locaux, pas dans la composante finie de l'automate
  produit;
- réaligner cette section sur:
  - `ProductState` dans `rocq/KairosOracle.v`,
  - `ProductStep` dans `rocq/KairosOracle.v`,
  - `product_state` dans `lib_v2/runtime/middle_end/product/product_types.mli`;
- reformuler les exemples de produit en conséquence.

## Remarque 2026-03-07-9

Texte utilisateur:
- `il faut refaire une passe pour s'assurer de la conformance vis à vis de la spécification Rocq pour ne plus avoir ce type d'erreur`

Interpretation:
- au-delà des corrections locales, le papier a besoin d'une passe systématique
  de conformité avec la formalisation Rocq actuelle;
- l'objectif est d'éviter les divergences de modèle (comme l'état du produit)
  qui réapparaissent ensuite dans le texte malgré les refactorings précédents.

Changements a faire:
- prévoir une passe de revue globale du papier contre `rocq/KairosOracle.v` et
  les interfaces Rocq pertinentes;
- vérifier au minimum la conformité des définitions suivantes:
  - sémantique de programme,
  - `StepCtx`,
  - `NodeSpecification`,
  - `ProductState`,
  - `ProductStep`,
  - obligations générées et rôle de `node_inv`;
- corriger toute présentation du PDF qui raconte une histoire plus forte, plus
  faible ou simplement différente de la formalisation Rocq actuelle;
- idéalement, ajouter en fin de passe une mini-checklist de conformité dans le
  cahier de laboratoire.
