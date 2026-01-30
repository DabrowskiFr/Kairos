# Methode moniteur pour les formules LTL (fragment G/X)

Ce document est autonome. Il decrit, du debut a la fin, la methode moniteur
utilisee dans le projet : construction d'un moniteur a partir d'une formule LTL
(fragment G/X), instrumentation du programme, et generation Why3 avec des
obligations de preuve non conditionnelles.

Hypotheses et fragment LTL
--------------------------
On se limite aux formules LTL construites avec :
- atomes propositionnels p sur l'etat courant,
- operateurs booléens (and, or, not, ->),
- X (next) et G (globally).

Les formules doivent etre en NNF (negations uniquement sur les atomes). On
rejette les negations au-dessus de G (not G phi) car F n'est pas dans le fragment.

Syntaxe (fragment G/X)
----------------------
ltl := True | False | Atom
     | not ltl
     | ltl and ltl
     | ltl or ltl
     | ltl -> ltl
     | X ltl
     | G ltl

Atomes et expressions historiques
---------------------------------
Un atome est une relation entre expressions historiques (HNow, HPre, HPreK,
scan/fold). En OBC, cela correspond aux formules dans les contrats, par exemple :
  {y} = pre(x)

Ces expressions historiques sont calculees par le programme via des variables
auxiliaires (pre, pre_k, scan/fold). Le moniteur ne reconstruit pas l'historique :
il consomme uniquement la valeur booleenne de chaque atome a l'instant courant.

Exemple d'atome
---------------
Atome : {y} = pre(x)
Dans le code, on calcule pre(x), puis on fixe :
  __atom_1 = (y = pre(x))
Le moniteur ne voit que __atom_1.

Semantique informelle
---------------------
Les formules sont interpretees sur des traces synchrones :
- X phi : phi est vraie au pas suivant.
- G phi : phi est vraie a tous les pas.

Remarque initial_only
---------------------
Dans la traduction Why3, une formule qui n'est pas sous G est appliquee
uniquement au premier pas (garde __first_step / old(__first_step)).
Cela ne change pas les formules de la forme G(phi).

Mise en NNF
-----------
La methode moniteur suppose les formules en NNF. La normalisation pousse les
negations jusqu'aux atomes.

Regles principales
------------------
- nnf(not (a and b)) = nnf(not a) or nnf(not b)
- nnf(not (a or b)) = nnf(not a) and nnf(not b)
- nnf(not (a -> b)) = nnf(a and not b)
- nnf(not (X a)) = X nnf(not a)
- nnf(not (G a)) = erreur (hors fragment)

Exemple
-------
Formule : not (X p or q)
NNF : X(not p) and (not q)

Algorithme 0 : NNF
------------------
Input  : formule phi
Output : formule en NNF

Algorithm NNF(phi):
  match phi with
    | True/False/Atom -> phi
    | Not Atom p -> Not Atom p
    | And(a,b) -> And(NNF(a), NNF(b))
    | Or(a,b) -> Or(NNF(a), NNF(b))
    | Imp(a,b) -> NNF(Or(Not a, b))
    | X a -> X(NNF(a))
    | G a -> G(NNF(a))
    | Not True -> False
    | Not False -> True
    | Not And(a,b) -> Or(NNF(Not a), NNF(Not b))
    | Not Or(a,b) -> And(NNF(Not a), NNF(Not b))
    | Not Imp(a,b) -> NNF(And(a, Not b))
    | Not X a -> X(NNF(Not a))
    | Not G a -> erreur

Progression (residuels)
-----------------------
La methode moniteur calcule des residuels (progression) :
  prog(phi, sigma) = formule a verifier au pas suivant.

Regles (fragment G/X)
---------------------
prog(p, sigma) = True  si sigma |= p, sinon False
prog(not p, sigma) = True si sigma !|= p, sinon False
prog(phi and psi, sigma) = prog(phi, sigma) and prog(psi, sigma)
prog(phi or psi, sigma) = prog(phi, sigma) or prog(psi, sigma)
prog(X phi, sigma) = phi
prog(G phi, sigma) = prog(phi, sigma) and G phi

Algorithme 1 : calcul des residuels
-----------------------------------
Input  : formule phi en NNF
Output : ensemble R des residuels, etat initial q0, etat mauvais bad

Algorithm ResidualStates(phi):
  R := empty_set
  worklist := [phi]
  while worklist not empty:
    r := pop(worklist)
    r := Simplify(r)
    if r not in R:
      add r to R
      for each valuation sigma over atoms:
        r_next := prog(r, sigma)
        r_next := Simplify(r_next)
        if r_next not in R:
          push r_next into worklist
  q0 := Simplify(phi)
  bad := False
  return (R, q0, bad)

Exemple (Algorithme 1)
----------------------
Formule : phi = (p and X q) or r.
On depile r = phi, puis on calcule ses successeurs :
- si r est vrai : prog(phi, sigma) = True.
- si r est faux et p est vrai : prog(phi, sigma) = q.
- si r est faux et p est faux : prog(phi, sigma) = False.
Ainsi, R = { phi, True, q, False } et q0 = phi.

Simplify (simplification logique)
---------------------------------
On simplifie pour garantir un ensemble fini et comparer les formules :
- True and x = x, False and x = False
- True or x = True, False or x = x
- x and x = x, x or x = x
- flatten and/or, tri canonique

Construction du moniteur
------------------------
On construit un automate deterministe dont les etats sont les residuels.

Algorithme 2 : moniteur deterministe
------------------------------------
Input  : ensemble R des residuels, etat initial q0
Output : moniteur (Q, q0, delta, bad)

Algorithm BuildMonitor(R, q0):
  Q := R
  for each q in Q:
    for each valuation sigma over atoms:
      q_next := Simplify(prog(q, sigma))
      delta[q, sigma] := q_next
  bad(q) := (q == False)
  return (Q, q0, delta, bad)

Exemple
-------
Formule : phi = (p and X q) or r, avec atomes {p,q,r}.
Les residuels calculés par l'Algorithme 1 sont :
  R = { phi, True, q, False }.
Dans l'Algorithme 2, pour l'etat phi :
- si r est vrai, prog(phi, sigma) = True ;
- si r est faux et p est vrai, prog(phi, sigma) = q ;
- si r est faux et p est faux, prog(phi, sigma) = False.
On compile donc les gardes :
  delta(phi, sigma) =
    True  si r
    q     si (not r) and p
    False si (not r) and (not p)
Pour l'etat q :
  delta(q, sigma) = True si q, sinon False.
Les etats True et False bouclent sur eux-memes, et bad = False.

Instrumentation du programme
----------------------------
On ajoute au programme :
- des booleens __atom_i pour chaque atome,
- des variables d'historique (pre/pre_k/scan/fold) deja gerees par l'infrastructure,
- un etat de moniteur __mon_state (int) encode par l'indice du residuel.

A chaque pas, on :
1) met a jour les atomes : __atom_i := eval_atom_i
2) met a jour le moniteur : __mon_state := delta(__mon_state, valuation)
3) verifie l'assertion de surete : __mon_state != bad

Exemple d'instrumentation
-------------------------
Si le moniteur a deux residuels (0 = ok, 1 = bad), on ajoute :
  if __mon_state = 0 then
    if __atom_2 then __mon_state <- 0 else __mon_state <- 1
  else if __mon_state = 1 then __mon_state <- 1
  assert __mon_state <> 1

Invariants du moniteur (correction generale)
--------------------------------------------
Pour chaque residuel r_i, on associe un invariant global :
  G( (__mon_state = i) -> r_i )

Cet invariant relie l'etat du moniteur au residuel correspondant et est
ajoute en Requires/Ensures. Il s'agit d'une obligation a prouver, pas d'une
hypothese externe.

Exemple
-------
Si r_0 = G(a) et r_1 = False, on ajoute :
  G( (__mon_state = 0) -> G(a) )
  G( (__mon_state = 1) -> False )

Generation Why3
---------------
Le fichier Why3 genere contient :
- la declaration des variables auxiliaires,
- la fonction init_vars,
- la fonction step avec contrats (requires/ensures),
- la mise a jour du moniteur et l'assertion __mon_state <> bad.

Algorithme 3 : compilation Why3
-------------------------------
Input  : programme OBC, moniteur
Output : fichier Why3

Algorithm CompileWhy3(program, monitor):
  declare var __mon_state
  add atom variables and assignments
  add monitor update
  add assert (__mon_state != bad)
  add invariants G(__mon_state=i -> r_i) as requires/ensures
  generate Why3 text

Construction des atomes
-----------------------
Chaque atome est remplace par un booleen __atom_i et relie a son expression.

Algorithm BuildAtoms(contracts):
  atoms := collect_atoms(contracts)
  for each atom a in atoms:
    name := __atom_i
    add local bool name
    add assignment: name := eval_atom(a)
    add invariant: name = eval_atom(a)
  return atom_map

Exemple
-------
Atome: {y} = pre(x)
Invariant: __atom_1 = (y = pre(x))

Compilation des contrats LTL (pre/post)
----------------------------------------
On derive des obligations pre/post a partir des contrats LTL. Cette
compilation est uniforme et ne depend pas de l'exemple.

Lemmes utilisateur
------------------
L'utilisateur peut ajouter des contrats `lemma` pour aider Why3. Un `lemma`
est traite comme un invariant a prouver : il genere des obligations en pre
et en post, mais n'est pas utilise pour construire le moniteur (il ne change
pas la formule LTL surveillee).

Regles (LtlSpec)
----------------
- True -> pas d'obligation
- False -> obligation False en post
- G a -> obligations sur a (pre et post)
- autre -> obligations sur le premier pas (via __first_step)

Le traitement de X utilise un decalage (shift) :
- si f contient X, on compile le post avec shift=0 (etat suivant)
- sinon, shift=1

Exemple
-------
f = X p
Pre(f)  = p au pas courant
Post(f) = p au pas suivant

Historique (pre/pre_k)
----------------------
Les variables d'historique sont mises a jour automatiquement et reliees par
ensures (chaines de old). Par exemple, pour pre_k(x, 2) :
  __pre_k1_x_1 = old(__pre_in_x)
  __pre_k1_x_2 = old(__pre_k1_x_1)

Ces liens sont generes de maniere uniforme, sans hypothese externe.

Resume de la correction
-----------------------
La correction absolue repose sur :
1) la correspondance residuels <-> LTL (progression correcte),
2) l'invariant global G(__mon_state = i -> r_i),
3) l'assertion de surete __mon_state != bad,
4) des obligations Why3 sans assume ni axiome.

Aucune hypothese d'environnement n'est necessaire : toutes les proprietes
utilisees sont soit calculees par le programme, soit prouvees par VCs.
