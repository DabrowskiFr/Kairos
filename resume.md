Projet
- Transpileur OCaml qui lit un fichier `.obc` (langage synchrone de noeuds avec automates) et génère un module WhyML par noeud pour la preuve statique des propriétés.

Langage accepte
- Noeud: `node <id>(params) returns (params)` puis contrats (`requires`, `ensures`, `assume`, `guarantee`), `locals`, `states`, `init`, `trans` et `end`.
- Instructions: affectation, `if ... then ... else ... end`, `skip`, `assert <ltl>` (actuellement ignoré dans le code exécutable).
- Expressions impératives: entiers/bools/réels, identifiants, binaires (+,-,*,/, comparaisons, and/or), unaires (neg/not), parenthèses.
- `hexpr` stateful pour les specs: `pre(e[,init])`, `scan(op,init,x)`, `scan1(op,x)`, `window(k,wop,x)`, `let x = h1 in h2` (+ `HNow`).

Spécifications et LTL
- Atomes: relation `hexpr rel hexpr` ou prédicats nommés (APred; pas encore gérés au codegen).
- LTL fragment: `true/false`, and/or/not, implication supprimée en NNF, `G` et `X` restreint à `X(atom)`; pas de Release.
- Sémantique de `X`: atomes sans `X` sont évalués en pré-état (via `old`), `X(atom)` en post-état du tick.
- Les formules `guarantee` (et combinées avec d’éventuels `assert`) sont conjuguées et traduites en moniteur ghost Why3:
  - Datatype `formula` (T/F/Lit/And/Or/Glob/Fin/Until) + fonction de progression `progress`.
  - Tableau de booléens `vals` alimenté par les atomes (pré/post) puis invariant `ok !phi` qui doit rester vrai; aucune vérification runtime.
  - Les `hexpr` utilisés uniquement dans les specs génèrent un état ghost dédié (refs, buffers de fenêtre) évalué avant/après le tick.

Génération Why3 (whygen.ml)
- Pour chaque noeud: types de base, refs locales/sorties initialisées, enum d’états, fonction `step` qui fait `match !st` et applique la première transition dont la garde est vraie (ou inconditionnelle).
- Instructions compilées en WhyML impératif; `assert` du corps n’a pas de code exécutable (contrôle par contrats uniquement).
- Fenetres implémentées de façon naïve sur `int` avec `Array.make k` et fonctions `wmax/wmin/wsum/wcount`.

Exemple fourni
- `examples/prefix_max.obc`: calcule un maximum préfixe avec contrat `guarantee G( X( scan1(max, x) >= 0 ) );`.

Construction / utilisation
- Dépendances: dune, menhir, ocamllex, `ppx_deriving.show`.
- Commandes typiques:
  - `dune build`
  - `dune exec obc2why3 -- examples/prefix_max.obc > out.why`

Limites repérées
- APred non géré au codegen; `assert` dans le corps ignoré pour l’instant.
- `window` limité aux entiers et calcul naïf; initialisation par défaut grossière pour `pre` sans init.
- `X` interdit sur entrées brutes (il faut passer par des `hexpr` ou des sorties/états); pas de Release ni d’équivalents.
