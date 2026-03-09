# Remarques de relecture pour `spec/rocq_oracle_model.tex`

Ce fichier sert de tampon editorial.

Principe:
- les remarques utilisateur sont d'abord consignees ici;
- chaque remarque est reformulee en interpretation editoriale;
- les changements a appliquer plus tard dans le papier sont listes explicitement;
- le fichier sert ensuite de base unique pour une reprise coherente du document.

## Remarque 2026-03-07-1

Texte utilisateur:
- `la partie intuitive et la partie formelle sont perturbantes, il vaut mieux introduire intuitivement et formellement les choses au fur et à mesure`

Interpretation:
- la structure actuelle separe trop fortement une premiere passe pedagogique et
  une seconde passe formelle;
- cette duplication oblige le lecteur a reconstruire lui-meme les liens entre
  deux presentations du meme contenu;
- il faut preferer une progression mixte:
  - intuition locale,
  - definition formelle immediate,
  - petit exemple ou consequence directe,
  - puis passage au concept suivant.

Problemes editoriaux identifies:
- redondance entre vue d'ensemble et reprise formelle;
- effet de desorientation quand une notion intuitive est reintroduite plus loin
  avec une definition differente ou plus precise;
- difficultes a comprendre l'ordre logique des dependances entre notions.

Changements a faire dans le papier:
- supprimer la separation rigide entre ``vue intuitive'' et ``modele formel'';
- reorganiser le document en progression lineaire par notions;
- pour chaque notion importante:
  - commencer par une intuition courte,
  - donner aussitot la definition mathematique,
  - illustrer par un exemple bref ou une consequence immediate;
- reduire les sections qui repassent integralement sur des contenus deja vus;
- inserer des transitions explicites entre notions pour indiquer pourquoi la
  suivante devient necessaire.

Impact attendu:
- lecture plus fluide;
- moins de repetition;
- meilleure retention des definitions;
- articulation plus nette entre pedagogie et formalisme.

## Remarque 2026-03-07-2

Texte utilisateur:
- `il n'y a pas de définition formelle de ce qu'est un programme, par exemple il manque les annotations utilisateur d'invariant d'état en plus de A et G. Il manque aussi une sémantique formelle d'exécution sur les flux des programmes à partir des transitions du programme`

Interpretation:
- le papier suppose trop vite la notion de ``programme'' alors qu'elle est
  centrale pour comprendre le produit `programme x A x G`;
- il faut definir mathematiquement:
  - les etats de programme,
  - les transitions de programme,
  - les entrees et sorties d'un tick,
  - les annotations utilisateur qui ne proviennent pas des automates,
  - la facon dont une suite d'entrees induit une execution sur flux.

Problemes editoriaux identifies:
- le lecteur ne sait pas exactement ce que porte la composante ``programme'' du
  produit;
- les obligations qui viennent des invariants utilisateur restent implicites;
- la notion de trace reactive du programme est utilisee avant d'etre definie;
- l'execution sur mot/flux est decrite intuitivement, mais pas comme relation
  ou fonction semantique precise.

Changements a faire dans le papier:
- ajouter une definition formelle explicite d'un programme reactif;
- inclure dans cette definition:
  - un ensemble d'etats de controle,
  - une memoire ou valuation d'etat,
  - une relation ou fonction de transition indexee par les entrees,
  - une fonction de sortie ou une sortie produite par la transition,
  - un ensemble d'annotations utilisateur d'invariant d'etat;
- distinguer clairement:
  - specification externe d'entree via `A`,
  - specification externe de garantie via `G`,
  - annotations internes fournies par l'utilisateur sur les etats/transitions du
    programme;
- definir formellement la semantique d'execution sur flux:
  - a partir d'un flux d'entree `u = (i(0), i(1), ...)`,
  - une suite d'etats `s_u(0), s_u(1), ...`,
  - une suite de sorties `o_u(0), o_u(1), ...`,
  - et la relation precise entre `s_u(k)`, `i(k)`, `o_u(k)` et `s_u(k+1)`;
- expliciter la notion de trace reactive associee au programme;
- relier ensuite seulement cette semantique au produit `programme x A x G`.

Questions de redaction a traiter au moment de la reprise:
- faut-il presenter le programme comme automate de Mealy, comme relation de pas
  reactive, ou comme structure abstraite plus generale?
- comment nommer proprement la famille des annotations utilisateur:
  `InvUser`, `UserInvariant`, `StateInvariant`, ou autre?
- faut-il distinguer des annotations d'etat et des annotations de transition?

Impact attendu:
- la composante ``programme'' du produit devient mathematiquement claire;
- les obligations non issues de `A` et `G` trouvent une place formelle explicite;
- le lecteur comprend mieux comment la trace reactive est generee avant meme de
  parler d'automates de surete.

## Remarque 2026-03-07-3

Texte utilisateur:
- `Les transisions d'automates devrait être décrites comme des relations logique, par exemple m' = i plutôt que m := i`

Interpretation:
- la notation actuelle de certaines transitions est trop imperative et donne
  l'impression d'un pseudo-code d'execution;
- dans ce document, il faut privilegier une presentation mathematique
  relationnelle des pas, avec etat source, observation, etat cible, et
  contraintes logiques entre valeurs courantes et suivantes.

Problemes editoriaux identifies:
- confusion possible entre:
  - une mise a jour imperative executee par une machine,
  - une contrainte logique caracterisant une transition admissible;
- perte d'uniformite entre le niveau mathematique du papier et la notation
  employee dans certains exemples d'automates;
- ambiguite sur le statut de la variable primee et sur le caractere relationnel
  des transitions.

Changements a faire dans le papier:
- remplacer autant que possible les notations de type affectation `x := e` par
  des formules relationnelles `x' = e`;
- presenter toute transition comme un predicat logique portant sur:
  - l'etat courant,
  - l'observation du tick,
  - l'etat suivant;
- harmoniser la notation entre:
  - transitions de programme,
  - transitions de `A`,
  - transitions de `G`,
  - pas du produit;
- expliciter des le debut la convention des variables primees:
  - `m` pour l'etat courant,
  - `m'` pour l'etat suivant;
- revoir les automates graphiques et les exemples pour qu'ils emploient tous ce
  style relationnel.

Impact attendu:
- style mathematique plus coherent;
- meilleure lisibilite des exemples;
- moindre confusion entre semantique declarative et pseudo-code imperative.

## Remarque 2026-03-07-4

Texte utilisateur:
- `Pour étape 2 : sémantique de flux, il faut montrer comment la sémantique permet d'avoir l'équation obtenue (c'est un co point fixe de la sémantique)`

Interpretation:
- la section sur la semantique de flux ne doit pas seulement poser l'equation de
  run ou de trace reactive comme une definition informelle;
- elle doit montrer comment cette equation emerge de la semantique elle-meme,
  en tant que caracterisation coinductive ou copoint fixe.

Problemes editoriaux identifies:
- l'equation de flux semble actuellement tomber du ciel;
- le lecteur ne voit pas pourquoi elle est bien definie ni quel est son statut
  mathematique exact;
- la relation entre transitions locales et comportement infini sur flux reste
  trop implicite.

Changements a faire dans le papier:
- expliciter le type mathematique des flux et des traces infinies;
- presenter la semantique d'execution comme operateur sur flux/traces;
- expliquer comment la suite d'etats et de sorties est caracterisee par une
  equation coinductive ou par un copoint fixe;
- relier cette presentation a l'equation de run effectivement utilisee ensuite;
- si possible, faire apparaitre une petite preuve ou au moins une justification
  de l'unicite / canonicite de la solution definie par cette equation.

Impact attendu:
- la semantique de flux devient mathematiquement fondee;
- le passage du pas local au comportement infini est beaucoup plus clair.

## Remarque 2026-03-07-5

Texte utilisateur:
- `il faut revoir les dessins des automates, il y a beaucoup trop de recouvrement`

Interpretation:
- le probleme n'est pas seulement cosmetique;
- les figures actuelles empechent de lire les etiquettes, les relations entre
  etats et parfois meme l'exemple semantique qu'elles sont censees porter.

Problemes editoriaux identifies:
- recouvrements de labels;
- densite excessive de texte dans les arcs;
- juxtaposition d'automates qui nuit a la lecture;
- manque de hierarchie visuelle entre etats, labels et commentaire.

Changements a faire dans le papier:
- refaire les automates avec une mise en page plus aeree;
- separer plus souvent les automates au lieu de les coller cote a cote;
- alleger les etiquettes d'arcs dans la figure et reporter le detail en dessous;
- privilegier des automates petits et lisibles plutot que des graphes compacts;
- pour les exemples complexes, remplacer eventuellement une figure unique par:
  - un automate du programme,
  - un automate `A`,
  - un automate `G`,
  - puis un sous-graphe de produit cible.

Impact attendu:
- figures enfin lisibles;
- meilleure comprehension des exemples;
- meilleure articulation entre dessin et texte explicatif.

## Remarque 2026-03-07-6

Texte utilisateur:
- `il faut expliquer de manière pseudo-algorithmique comment on génère les obligations pour tous les cas`

Interpretation:
- la generation des obligations ne doit pas apparaitre comme une taxonomie ou
  une enumeration statique;
- il faut decrire un veritable procede de construction, suffisamment explicite
  pour que le lecteur puisse suivre comment l'outil passe du produit aux
  obligations concretement.

Problemes editoriaux identifies:
- trop de place donnee aux familles d'obligations et pas assez a leur
  construction;
- manque de vision procedurale;
- absence d'une couverture explicite ``pour tous les cas''.

Changements a faire dans le papier:
- ajouter un schema pseudo-algorithmique de generation;
- decrire en entree:
  - le programme,
  - `A`,
  - `G`,
  - l'etat ou l'ensemble de pas produit explores;
- decrire en sortie:
  - la collection d'obligations generees,
  - classees par role;
- presenter les cas de generation au moins selon:
  - pas sur,
  - pas menant a `bad_G`,
  - pas menant a `bad_A`,
  - pas elimine ou pruned,
  - annotations utilisateur a reporter;
- montrer comment chaque cas engendre:
  - une obligation,
  - une contrainte de coherence,
  - ou aucune obligation;
- relier explicitement cet algorithme a la taxonomie abstraite deja introduite.

Impact attendu:
- l'extraction des obligations devient comprensible comme processus;
- la couverture des cas cesse de ressembler a une simple enumeration.

## Remarque 2026-03-07-7

Texte utilisateur:
- `il faut mieux expliquer la notion de pas dangereux, comment elle se relie à la sémantique et aux automates, pourquoi ils sont problématique. Et dans les exemples pour cette notion, redéssiner tout l'automate produit et montrer comment on extrait l'information. De manière générale, il faut toujours revenir au programme et à l'automate produit pour montrer comment on génére les obligations`

Interpretation:
- la notion de ``pas dangereux'' est au coeur de la reduction locale de Kairos,
  mais le document ne lui donne pas encore le statut central qu'elle merite;
- il faut la definir a la fois semantiquement, automatiqument et operatoirement.

Problemes editoriaux identifies:
- lien insuffisant entre:
  - violation globale de `G`,
  - transition locale vers `bad_G`,
  - obligation extraite;
- les exemples ne montrent pas assez clairement le produit complet;
- on ne voit pas assez que l'obligation vient d'un pas du produit, et non d'une
  formule isolee tombee du ciel.

Changements a faire dans le papier:
- introduire une definition formelle nette du pas dangereux;
- expliquer:
  - ce qu'il signifie dans la semantique du produit,
  - pourquoi il est dangereux pour la correction,
  - et pourquoi il faut le bloquer par une obligation locale;
- relier explicitement cette notion:
  - a l'etat courant du programme,
  - a la transition de programme choisie,
  - a l'avance de `A`,
  - a l'avance de `G`,
  - a l'atteinte de `bad_G`;
- dans les exemples, redessiner le produit complet ou au moins le sous-graphe
  utile du produit;
- pour chaque exemple:
  - identifier l'etat produit source,
  - montrer le pas dangereux,
  - ecrire la contrainte logique qui caracterise le matching de ce pas,
  - montrer l'obligation extraite;
- faire de maniere generale du programme et du produit les objets de reference
  a chaque fois qu'on parle de generation d'obligations.

Impact attendu:
- la reduction locale devient beaucoup plus concrete;
- le lecteur comprend enfin pourquoi une obligation locale est la negation d'un
  pas produit dangereux realisable;
- les exemples deviennent demonstratifs, pas seulement illustratifs.

## Remarque 2026-03-07-8

Texte utilisateur:
- `dans les transitions on note (t,s,m,i,s′,m′,o), on pourrait introduire une notation ((s,m), i) ->_t ((s',m'), o) pour la lisitiblité`

Interpretation:
- la forme tuplee actuelle des pas de programme est trop compacte et masque la
  structure conceptuelle du tick;
- il faut faire apparaitre plus clairement qu'un pas prend un etat courant
  compose `(s,m)` et une entree `i`, puis produit une sortie `o` et un etat
  suivant `(s',m')`, sous l'etiquette de transition `t`.

Problemes editoriaux identifies:
- lecture difficile des definitions de transition;
- faible visibilite de la separation entre:
  - etat courant,
  - entree,
  - transition choisie,
  - etat suivant,
  - sortie;
- reutilisation peu lisible de la notation tuplee dans les sections sur le
  produit et les obligations.

Changements a faire dans le papier:
- introduire une notation principale du style
  `((s,m), i) ->_t ((s',m'), o)` pour les pas de programme;
- releguer la notation tuplee `(t,s,m,i,s',m',o)` a un encodage auxiliaire si
  elle reste utile;
- reprendre avec cette notation:
  - la definition du pas de programme,
  - la semantique de flux,
  - la definition du pas produit,
  - la presentation des pas dangereux,
  - les exemples d'extraction d'obligations;
- harmoniser cette notation avec les transitions relationnelles deja adoptees
  pour les automates.

Impact attendu:
- meilleure lisibilite locale des formules;
- meilleure comprehension de la structure operationnelle d'un tick;
- meilleur alignement entre texte, figures et exemples.

## Remarque 2026-03-07-9

Texte utilisateur:
- `dans un programme Inv doit pouvoir porter sur l'historique des mémoire (e.g y = prev x), pas seulement la mémoire courante, S -> P(M -> B) ==> S -> P(M*). Ce serait plus en phasse avec l'implémentation et la formalisation non ? A moins qu'il ne porte sur l'état courant avec les variables auxiliaires de décallage ? Mais pour l'utilisateur ce n'est pas l'intuition.`

Interpretation:
- la presentation actuelle des invariants de noeud est probablement trop
  restreinte si elle les fait porter seulement sur la memoire courante `M`;
- du point de vue utilisateur, un invariant ou une specification locale peut
  naturellement parler d'historique, par exemple via `prev x` ou `pre_k(x,d)`;
- il faut donc presenter la specification de noeud au niveau semantique comme
  portant sur des histories ou contextes enrichis, meme si l'implementation
  et certains morceaux de la formalisation les compilent ensuite via des
  variables auxiliaires de decalage dans l'etat courant.

Problemes editoriaux identifies:
- decalage entre l'intuition utilisateur et la presentation mathematique si
  `Inv` est limite a `S -> P(M -> B)`;
- risque de faire croire que seules les memoires courantes sont specifiables;
- confusion possible entre:
  - la specification source exprimee avec du passe,
  - et sa compilation vers des variables d'etat auxiliaires.

Changements a faire dans le papier:
- remplacer la vision naive `Inv : S -> P(M -> B)` par une presentation plus
  riche, par exemple `Inv : S -> P(H -> B)` ou `Inv : S -> P(M* -> B)` selon la
  notation retenue pour l'historique;
- definir explicitement ce qu'est le contexte historique accessible aux
  invariants de noeud:
  - historique d'entrees,
  - historique de sorties,
  - historique de memoire ou contexte de tick enrichi;
- expliquer que, semantiquement, les invariants portent sur ce contexte
  historique, afin de rester alignes avec l'intuition utilisateur;
- expliquer separement que l'implementation peut compiler ces references au
  passe via des variables auxiliaires de decalage ou des memoires ghosts;
- verifier l'alignement avec la formalisation Rocq:
  - soit en presentant `Inv` directement sur un contexte historique,
  - soit en expliquant proprement la compilation semantiquement preservatrice
    vers un etat courant enrichi.

Question de redaction a trancher lors de la reprise:
- faut-il faire porter `Inv` sur un historique abstrait `H`,
  ou sur un etat courant deja enrichi de variables de memoisation du passe?
  L'orientation editoriale a privilegier est l'intuition utilisateur:
  specification sur l'historique, puis compilation separee.

Impact attendu:
- meilleure adequation entre le papier et l'intuition des specifications
  utilisateur;
- meilleur alignement avec les exemples du type `y = prev x`;
- distinction plus propre entre niveau semantique source et encodage backend.

## Remarque 2026-03-07-10

Texte utilisateur:
- `stepP (s,m,i) := selectP (s,m,i) ??? Quel intéret d'avoir deux définitions ?`

Interpretation:
- la presentation actuelle introduit peut-etre un doublon inutile entre une
  fonction de selection et une fonction de pas qui lui est identique;
- si `step_P` n'ajoute aucun contenu semantique au-dela de `select_P`, alors le
  papier gagne a n'en garder qu'une seule comme primitive, ou a justifier tres
  explicitement leur difference de role.

Problemes editoriaux identifies:
- impression de duplication gratuite dans les definitions de base;
- risque de faire croire qu'il existe deux niveaux semantiques distincts alors
  qu'il s'agit du meme objet;
- surcharge de notation des les premieres sections.

Changements a faire dans le papier:
- soit supprimer l'une des deux notations et garder une seule primitive;
- soit expliquer clairement:
  - que `select_P` est une fonction de choix d'identifiant de transition,
  - tandis que `step_P` est le pas complet avec source/cible/sortie;
- en tout etat de cause, eviter une definition tautologique du type
  `step_P := select_P` sans gain explicatif reel;
- simplifier ensuite les equations de semantique de flux en reutilisant la
  notation retenue de maniere uniforme.

Impact attendu:
- modele de base plus compact;
- moins de bruit notationnel;
- meilleure entree dans la semantique du programme.

## Remarque 2026-03-07-11

Texte utilisateur:
- `"TickCtx désigne le type abstrait des contextes locaux de tick dérivés de la trace d’exécution" ce n'est pas clair, on ne sait pas ce qu'est un contexte local de tick ni comment ils sont dérivés de la trace d'exécution`

Interpretation:
- la formulation actuelle est trop elliptique: elle nomme `TickCtx` sans en
  donner une vraie definition conceptuelle ni une construction mathematique
  explicite;
- il faut expliquer ce qu'est un ``contexte local de tick'', pourquoi il est
  local, quelles composantes il contient, et comment il est obtenu a partir de
  l'execution du programme et de la trace associee.

Problemes editoriaux identifies:
- `TickCtx` apparait comme une boite noire;
- le lecteur ne comprend pas la difference entre:
  - configuration,
  - observation,
  - trace reactive,
  - contexte local de tick;
- l'articulation entre semantique du programme et interpretation des
  specifications reste trop implicite.

Changements a faire dans le papier:
- remplacer la formule vague ``type abstrait des contextes locaux de tick'' par
  une definition explicite;
- introduire d'abord l'intuition:
  - un contexte local de tick est la fenetre minimale sur l'execution autour du
    tick `k` permettant d'interpreter les obligations et les formules locales;
- donner ensuite une definition mathematique concrete, par exemple comme
  n-uplet contenant:
  - l'indice `k`,
  - la configuration courante,
  - l'entree courante,
  - la sortie courante,
  - la configuration suivante,
  - et, si besoin, l'acces au passe via la trace;
- montrer explicitement comment `ctx_u(k)` est construit a partir de
  `cfg_u(k)`, `u(k)`, `o_u(k)` et `cfg_u(k+1)`;
- expliquer enfin que les operateurs de passe (`prev`, `pre_k`) se lisent via
  la famille des contextes `ctx_u(0), ctx_u(1), ...`, pas via une structure
  magique supplementaire.

Impact attendu:
- `TickCtx` devient un objet comprehensible;
- le lecteur voit comment la specification se branche sur l'execution;
- la semantique des obligations locales devient plus concrete.

## Remarque 2026-03-07-12

Texte utilisateur:
- `hd(Φu(ρ)) = (s0,m0), oP (s0,m0,u(0)),`
- `tl(Φu(ρ))(k) = ρ′(k),`
- `on ne sait pas ce qu'est oP ni rho'`

Interpretation:
- la presentation coinductive actuelle introduit trop vite des notations
  auxiliaires non definies (`o_P`, `rho'`);
- au lieu d'eclairer la semantique de flux, cette ecriture la rend plus opaque.

Problemes editoriaux identifies:
- `o_P` apparait sans lien explicite avec la semantique de pas du programme;
- `rho'` est introduit comme un nouvel objet sans definition mathematique
  precise;
- l'operateur `Phi_u` ressemble alors a une specification informelle plutot
  qu'a une vraie definition.

Changements a faire dans le papier:
- definir explicitement `o_P` avant son premier usage, ou le remplacer par une
  projection claire du pas de programme retenu;
- eliminer `rho'` si possible, en donnant une equation de queue plus directe;
- sinon, definir `rho'` comme le flux obtenu pour la configuration initiale
  suivante et le suffixe de l'entree, avec une notation stable;
- verifier que toutes les notations utilisees dans l'equation coinductive ont
  deja ete introduites:
  - projections du pas,
  - tete et queue de flux,
  - suffixe du flux d'entree.

Impact attendu:
- la sémantique coinductive devient lisible;
- le lecteur peut reconstruire effectivement la trace sans deviner les objets
  auxiliaires;
- l'introduction de la semantique sur flux gagne en rigueur.
