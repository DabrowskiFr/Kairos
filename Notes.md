
- construction de l'automate
    + noeuds : résidus
    + arcs : pour chaque résiduel et valuation, formule f qui donne le résiduel cible 

- instrumentation du programme par le moniteur 
    pour chaque état du moniteur et chaque transition, tester la formule f et passer dans l'état correspondant.

- Si on arrive à prouver que le moniteur ne passe jamais dans l'état Bad alors le programme satisfait la spécification LTL.

- En pratique why3 ne pourra pas prouver ce résultat sans informations supplémentaires. On distingue deux types d'informations
    + celles provenant du moniteur 
        + pour chaque état du moniteur, pour chaque état précédent possible un require donnant la formule de la transition.
        la formule concernant la fin de l'étape précédente il faut
            décaller ses opérateurs d'historique d'un pas en avant.
        + pour chaque état du moniteur, pour chaque état suivant possible un ensures donnant la formule de la transition
    + celles données par l'utilisateur sous forme d'invariant, et de contrat requires/ensures au niveau des transitions. Si un état de l'automate du programme à une transition vers un autre, il faut que le ensures du premier implique le requires du second.
    A nouveau la formule du ensures doit être décallé d'un pas en avant pour correspondre au début de l'instant du successeur.

    utilisateur: ensures -> requires avec décallage

Informations à ajouter : 
    quel sont les successeurs et prédécesseurs de chaque état
    un calcul du produit de l'automate de la formule et de l'automate
    des états du programme permet de calculer cette information.

Resume plus fidele de l'implementation actuelle (avec exemples sur delay_int):

- La spec LTL est traduite en automate de residus. Le moniteur est instrumente
  dans le programme via un etat ghost (__mon_state) mis a jour a chaque pas
  en fonction des atomes; on prouve ensuite que __mon_state n'atteint pas Bad.
  Exemple delay_int: la garantie "X G(y = pre(x))" produit un automate avec
  des residus Mon0/Mon1/Mon2, et une assertion "mon_state <> Mon2".

- Les obligations ajoutees dans Why3 ne sont pas des requires/ensures explicites
  par etat de moniteur: on encode l'automate via les mises a jour + assertions
  et des conditions de compatibilite (st/mon_state).
  Exemple delay_int: on met a jour mon_state dans chaque branche Run/Init et on
  ajoute des ensures/compatibilite du type (st=Run -> mon_state=Mon1 ou Mon2).

- Pour relier les transitions du programme, on ajoute des lemmes de coherence:
  (ensures du pas courant, decales d'un pas vers l'avant) => requires des
  transitions successeurs. Ces lemmes sont emets comme postconditions Why3.
  Exemple delay_int: le ensures "prev = x" de Run->Run est decale et doit impliquer
  le requires "prev = pre(x)" du pas suivant.

- Les requires de transitions sont aussi injectes comme preconditions du step,
  gardees par l'etat source (st = src).
  Exemple delay_int: le requires "prev = pre(x)" de Run->Run devient un requires
  Why3 guardee par (st = Run).

- Pas de produit d'automates explicite dans le code: la construction par residus
  suffit pour le moniteur.
  Exemple delay_int: on ne construit pas (automate formule x automate etats),
  on se contente des residus de "X G(y = pre(x))".

Detail algorithmique (contrat de step, par type):

Preconditions (requires)
1) Contract requires (noeud)
   - pour chaque Requires/Assume au niveau du noeud:
     rel = ltl_relational(f), frag = ltl_spec(rel)
     ajouter frag.pre (avec k_guard et garde __first_step si besoin)
2) Transition requires
   - pour chaque transition src->dst et chaque Requires f dans la transition:
     frag.pre comme ci-dessus
     ajouter (st = src -> frag.pre)
3) Monitor / Atoms / Compatibility
   - atomes: atom_i = (formule)
   - compatibilite: st=... -> mon_state=...
   - obligations moniteur en pre (residus + step_count/first_step)
4) User invariants / instance links (pre)
   - invariants utilisateur et liens d'instances en preconditions

Postconditions (ensures)
1) Contract ensures (noeud)
   - pour chaque Ensures/Guarantee au niveau du noeud:
     frag.post (avec k_guard/first_step)
2) Lemmes (noeud)
   - chaque Lemma est encode comme ensures (et ajoute aussi un pre via frag.pre)
3) Transition lemmas (coherence)
   - pour chaque transition src->dst:
     ensures_all = ensures(noeud) U ensures(transition)
     ensures_all_shifted = decaler d'un pas en avant
     pour chaque Requires g des transitions sortant de dst:
       ajouter lemma: ensures_all_shifted -> g
4) Monitor / Atoms / Compatibility (post)
   - atomes, compatibilite, assertions moniteur
5) History + inputs
   - pre_k history
   - __pre_old_x = old(__pre_in_x)
   - __pre_in_x = x
6) Result
   - result = y (ou tuple)


--------------------
Au début d’un pas, on a encore les anciennes valeurs des ghost :
__pre_in_x = x du pas précédent
__pre_old_x = x d’il y a deux pas
Puis on fait les updates ghost :
__pre_old_x <- __pre_in_x
__pre_in_x <- x (entrée courante)
---------------------------------------------------