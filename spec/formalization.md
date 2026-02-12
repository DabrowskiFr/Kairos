# Formalisation Abstraite de OBC vers OBC+

## 1. Objectif et portée

Ce document formalise le passage d'un noeud OBC source vers un noeud OBC+ enrichi
(cohérence des contrats, obligations monitor/compatibilité, obligations backend).

Avant d'énoncer le résultat final, on fixe les notations de haut niveau utilisées dans tout le texte.

### Notations principales (domaine et rôle)

- \(N\) : noeud source (programme OBC avant enrichissement).
- \(N^+\) : noeud enrichi (programme OBC+ après ajout d'obligations).
- \(\mathcal I\) : ensemble des variables d'entrée du noeud.
- \(A\) : hypothèse de contrat (formule temporelle sur les entrées).
- \(G\) : garantie de contrat (formule temporelle sur le comportement du noeud).
- \(\rho\) : suite des états internes successifs du noeud.
Intuition : mémoire + état de contrôle au fil des pas.
- \(\iota : \mathbb N \to Store_{\mathcal I}\) : flux d'entrées.
Intuition : valeur des entrées à chaque instant.
- \(\omega\) : flux de sorties produit par le noeud.
- \(\pi := (\rho,\iota,\omega)\) : exécution complète.
- \(\pi\downarrow_{\mathcal I} := \iota\) : projection de l'exécution sur les seules entrées.
- \(\pi \models \Phi\) : la formule temporelle \(\Phi\) est satisfaite par \(\pi\).

### Vue d'ensemble du langage OBC (intuition)

Un noeud OBC est un composant synchrone à états finis :

- il lit des entrées à chaque pas d'horloge,
- il met à jour son état interne,
- il produit des sorties,
- il choisit une transition de contrôle selon l'état courant (et éventuellement une garde).

Les contrats de transitions (`require`/`ensure`) expriment des propriétés locales d'un pas.
Les contrats LTL de noeud (\(A\), \(G\)) expriment des propriétés temporelles globales sur toute l'exécution.

### Ce que l'on veut vérifier

On veut établir que le noeud satisfait sa garantie temporelle \(G\) pour toute exécution dont
les entrées satisfont l'hypothèse \(A\), c'est-à-dire :

\[
\forall \pi,\; (\pi\downarrow_{\mathcal I}\models A)\Rightarrow(\pi\models G).
\]

Intuitivement : sous les bons scénarios d'entrée, le comportement du programme reste toujours conforme au contrat.

### Méthode de vérification (intuition)

La méthode suit trois idées :

1. **ramener le temporel à un monitor** :
   compiler \((A,G)\) en un automate monitor avec un état `bad` représentant la violation ;
2. **instrumenter le programme** :
   ajouter des obligations de support (`Coherency`, `Compatibility`, `Monitor`) pour relier
   l'exécution du code à celle du monitor ;
3. **prouver les obligations générées** :
   générer des VCs via WP ; la preuve de ces VCs établit notamment l'inatteignabilité de `bad`
   (`NoBad`), puis \(A \Rightarrow G\) via la correction du monitor (`MonCorr`).

### Résultat visé

Le théorème de correction de bout en bout visé est :

\[
\forall \pi,\; (\pi\downarrow_{\mathcal I} \models A) \Rightarrow (\pi \models G).
\]

Lecture intuitive :
pour toute exécution possible du programme, si le flux d'entrées respecte l'hypothèse \(A\),
alors la garantie \(G\) est satisfaite.

### Intuition de la méthode (vue d'ensemble)

Avant les détails formels, l'idée globale est la suivante :

1. on part des formules LTL de contrat (\(A\), \(G\)) ;
2. on construit un automate monitor \(\mathcal M\) qui encode la violation potentielle du contrat
   (avec un état `bad`) ;
3. on instrumente le programme OBC avec une variable d'état monitor et des obligations logiques
   (`Compatibility`, `Monitor`, `NoBad`) qui forcent la cohérence entre exécution programme et
   exécution monitor ;
4. on génère des obligations de preuve (WP/VC) sur ce programme instrumenté ;
5. si ces obligations sont prouvées, on montre que l'état `bad` n'est jamais atteint ;
6. par correction de la construction monitor, l'absence de `bad` sous l'hypothèse \(A\)
   implique la satisfaction de \(G\).

En résumé : au lieu de prouver directement \(A \Rightarrow G\) sur le code brut, on prouve que
l'instrumentation monitor est respectée et que `bad` est inatteignable, ce qui donne \(G\).

### Rôle des obligations : objectif vs support

On distingue deux familles :

- **obligation objectif** : `NoBad` (prouver que l'état monitor `bad` est inatteignable) ;
- **obligations de support** : `Coherency`, `Compatibility`, `Monitor` (et obligations WP associées),
  qui servent à rendre la preuve de `NoBad` correcte et exploitable vis-à-vis de la sémantique du programme.

Le fil logique est :

\[
\text{Support prouvé} \;\Longrightarrow\; \text{NoBad prouvé}
\;\Longrightarrow\; (A \Rightarrow G) \text{ via } MonCorr.
\]

### Théorème cible (Tfinal)

\[
T_{final}:\quad
\forall \pi,\; (\pi\downarrow_{\mathcal I} \models A) \Rightarrow (\pi \models G).
\]

### Plan de preuve (backward)

Pour prouver \(T_{final}\), on isole les résultats intermédiaires suivants :

- **Préservation de l'exécution** (\(L_{proj}\)) :
  pour toute exécution instrumentée \(\pi^+\) de \(N^+\), la projection
  \(\pi^+\downarrow N\) est une exécution valide de \(N\) (mêmes pas observables
  sur les variables du programme source).
- **Adéquation monitor** (\(L_{mon}\)) :
  les obligations `Compatibility`/`Monitor` suffisent à relier \(A\) et \(G\) sur \(N^+\).
- **Cohérence locale des contrats** (\(L_{coh}\)) :
  les obligations ajoutées propagent les `require` d'une transition vers la suivante.
- **Alignement temporel du shift** (\(L_{shift}\)) :
  \(Shift_{\mathcal I}\) exprime correctement le passage du pas \(i\) au pas \(i+1\).
- **Définissabilité des historiques** (\(L_{prek}\)) :
  les occurrences `pre_k` utilisées dans les obligations ne sont jamais évaluées hors domaine.

Chaîne de dépendance visée :

\[
L_{prek} \land L_{shift} \land L_{coh} \land L_{mon} \land L_{proj}
\;\Longrightarrow\;
T_{final}.
\]

## 2. Running examples

### Exemple D (inspiré de `delay_int`)

On considère un noeud abstrait \(N_D\) avec :

- états \(S_D = \{Init, Run\}\), état initial \(s_0 = Init\),
- une entrée \(x \in \mathcal I\), une sortie \(y \in \mathcal O\), une variable locale \(prev\),
- transitions :
  - \(t_0 = (Exec_{t_0}, Ctr^u_{t_0})\), avec
    \(Exec_{t_0}=(Init,Run,Pre_{t_0},Post_{t_0})\),
    \(Pre_{t_0}\equiv true\),
    \(Post_{t_0}\equiv (prev' = x)\),
    \(Req^u_{t_0}\equiv true\),
    \(Ens^u_{t_0}\equiv (prev' = x)\),
  - \(t_1 = (Exec_{t_1}, Ctr^u_{t_1})\), avec
    \(Exec_{t_1}=(Run,Run,Pre_{t_1},Post_{t_1})\),
    \(Pre_{t_1}\equiv (prev = pre_k(x,1))\),
    \(Post_{t_1}\equiv (prev' = x)\),
    \(Req^u_{t_1}\equiv (prev = pre_k(x,1))\),
    \(Ens^u_{t_1}\equiv (prev' = x)\),
- contrat de noeud (garantie) : \(G_D := X\,G(y = pre_k(x,1))\).

Intuition : la transition de boucle \(t_1\) contraint explicitement l'historique d'entrée.

### Exemple T (inspiré de `toggle`)

On considère un noeud abstrait \(N_T\) avec :

- états \(S_T = \{Init, Run\}\), état initial \(s_0 = Init\),
- sortie \(y\), pas de `pre_k` dans les contrats de transition utilisateur,
- transitions :
  - \(u_0 = (Exec_{u_0}, Ctr^u_{u_0})\), avec
    \(Exec_{u_0}=(Init,Run,Pre_{u_0},Post_{u_0})\),
    \(Pre_{u_0}\equiv true\),
    \(Post_{u_0}\equiv (y' = 0)\),
    \(Req^u_{u_0}\equiv true\),
    \(Ens^u_{u_0}\equiv true\),
  - \(u_1 = (Exec_{u_1}, Ctr^u_{u_1})\), avec
    \(Exec_{u_1}=(Run,Run,Pre_{u_1},Post_{u_1})\),
    \(Pre_{u_1}\equiv true\),
    \(Post_{u_1}\equiv ((y=0 \land y'=1)\lor(y=1 \land y'=0))\),
    \(Req^u_{u_1}\equiv true\),
    \(Ens^u_{u_1}\equiv true\),
- garanties de noeud :
  - \(G_{T,0}: y=0\) au démarrage,
  - \(G_{T,1}: G(y=0 \Rightarrow X(y=1))\),
  - \(G_{T,2}: G(y=1 \Rightarrow X(y=0))\).

Intuition : pas de contrainte historique utilisateur, mais des obligations monitor/compatibilité issues des garanties LTL.

## 3. Modèle abstrait OBC

### Définition 3.1 - Sortes

On fixe les sortes suivantes :

- `State` : états de contrôle.
- `Var` : variables.
- `Val` : valeurs.
- `Store` : valuations \(Var \to Val\).

Une configuration est :

\[
Config := State \times Store
\]

### Définition 3.2 - Transition

On sépare exécution et contrat utilisateur.

\[
TransExec := (src, dst, Pre, Post)
\]
\[
TransCtr^u := (Req^u, Ens^u)
\]
\[
t := (Exec_t, Ctr_t^u)
\]

avec :

- \(Exec_t = (src(t), dst(t), Pre_t, Post_t)\).
- \(Ctr_t^u = (Req_t^u, Ens_t^u)\).

### Définition 3.3 - Noeud

\[
NodeExec := (S, s_0, T, \mathcal V, \mathcal I, \mathcal O)
\]
\[
NodeCtr^u := (A, G)
\]
\[
N := (Exec_N, Ctr_N^u)
\]

avec :

- \(S\) fini, \(s_0 \in S\), \(T\) fini.
- \(\mathcal V\) variables, \(\mathcal I\subseteq\mathcal V\) entrées, \(\mathcal O\subseteq\mathcal V\) sorties.
- \(A\) hypothèse LTL utilisateur, \(G\) garantie LTL utilisateur.

## 4. Sémantique détaillée (step et flux)

Cette section fixe une sémantique suffisamment précise pour justifier les lemmes de cohérence
(`Shift`, `pre_k`, WP/VC) utilisés dans la preuve finale.

### Définition 4.1 - Configurations observables et internes

On décompose les variables d'un noeud en :

- entrées \(\mathcal I\),
- sorties \(\mathcal O\),
- mémoire interne \(\mathcal M := \mathcal V \setminus (\mathcal I \cup \mathcal O)\).

Une configuration interne est :

\[
Conf := S \times Store_{\mathcal M \cup \mathcal O}
\]

où \(Store_X\) est l'ensemble des valuations des variables de \(X\).

Intuition : les entrées ne sont pas stockées comme mémoire persistante du noeud, elles sont fournies
par l'environnement à chaque instant.

### Définition 4.2 - Flux d'entrées et flux de sorties

Un flux d'entrées est une fonction :

\[
\iota : \mathbb N \to Store_{\mathcal I}.
\]

Un flux de sorties est une fonction :

\[
\omega : \mathbb N \to Store_{\mathcal O}.
\]

Le but sémantique d'un noeud est : à partir d'un état initial et d'un flux \(\iota\), produire
une exécution interne et un flux \(\omega\).

### Définition 4.3 - Sémantique d'un pas (`step`)

Pour un instant \(i\), on note \(in_i := \iota(i)\).  
On écrit :

\[
(s_i,\mu_i) \xRightarrow[in_i]{step,t_i} (s_{i+1},\mu_{i+1},out_i)
\]

ssi il existe une transition \(t_i\in T\) telle que :

1. \(src(t_i)=s_i\), \(dst(t_i)=s_{i+1}\),
2. \(Pre_{t_i}(s_i,\mu_i,in_i)\) est vraie,
3. \(Post_{t_i}(s_i,\mu_i,in_i,s_{i+1},\mu_{i+1},out_i)\) est vraie.

Ici \(out_i\in Store_{\mathcal O}\) est la sortie produite au pas \(i\).

### Hypothèse 4.4 - Progression et unicité du pas

Pour chaque couple \((s_i,\mu_i)\) et entrée \(in_i\), il existe exactement un triplet
\((t_i,s_{i+1},\mu_{i+1},out_i)\) satisfaisant 4.3.

Cette hypothèse capture la discipline « un pas synchrone bien défini » :
pas de blocage et pas de non-déterminisme observable.

### Définition 4.5 - Exécution induite par un flux d'entrées

Étant donnés \((s_0,\mu_0)\) et \(\iota\), une exécution est la suite :

\[
\rho = (s_0,\mu_0),(s_1,\mu_1),(s_2,\mu_2),\dots
\]

telle que, pour tout \(i\), il existe \(out_i\) vérifiant 4.3.
Le flux de sorties induit est \(\omega(i)=out_i\).

On note alors :

\[
Run(N,s_0,\mu_0,\iota) = (\rho,\omega).
\]

### Définition 4.6 - Environnement d'évaluation au pas \(i\)

Pour évaluer les formules, on utilise un environnement temporel \(Env_i\) construit à partir de
\((\rho,\iota,\omega)\) :

- pour \(x\in\mathcal I\), \(Env_i(x)=\iota(i)(x)\),
- pour \(x\in\mathcal O\cup\mathcal M\), \(Env_i(x)\) est lu dans \(\mu_i\) (ou \(\omega(i)\) pour les sorties selon la convention d'encodage).

On note \(\mathrm{Eval}(\rho,\iota,\omega,i,e)\) l'évaluation d'une expression \(e\) au pas \(i\).

### Définition 4.7 - Sémantique de `pre_k`

Pour \(k\ge 1\), `pre_k(x,k)` au pas \(i\) est définie ssi \(i\ge k\), et :

\[
\mathrm{Eval}(\rho,\iota,\omega,i,pre_k(x,k)) = \mathrm{Eval}(\rho,\iota,\omega,i-k,Now(x)).
\]

Prédicat de définissabilité :

\[
Defined(\rho,\iota,\omega,i,pre_k(x,k)) \iff i\ge k.
\]

### Définition 4.8 - Satisfaction des formules

On note :

- \((\rho,\iota,\omega),i \models \varphi\) pour une formule instantanée \(\varphi\) au pas \(i\),
- \((\rho,\iota,\omega) \models \Phi\) pour une formule temporelle LTL \(\Phi\),
- \(\iota \models A\) quand la formule d'hypothèse \(A\) (sur entrées) est satisfaite par le flux d'entrées,
- \((\rho,\iota,\omega) \models G\) quand la garantie \(G\) est satisfaite par l'exécution complète.

Notation abrégée (utilisée dans la suite) :

\[
\pi := (\rho,\iota,\omega),\qquad
\pi\downarrow_{\mathcal I} := \iota,\qquad
\mathrm{Eval}(\pi,i,e) := \mathrm{Eval}(\rho,\iota,\omega,i,e).
\]

Dans le théorème final, \(A\) est donc interprétée sur le flux d'entrées \(\iota\), et \(G\) sur l'exécution complète.

### Définition 4.9 - Point d'évaluation des contrats de transition

Pour une transition \(t_i\) exécutée entre \(i\) et \(i+1\) :

- `require` est évalué en pré-état \((s_i,\mu_i)\) avec entrée \(in_i\),
- `ensure` est évalué en post-état \((s_{i+1},\mu_{i+1})\) (et peut référencer le pré-état selon la logique d'encodage).

### Lemme 4.10 - Sens du décalage \(Shift_{\mathcal I}\)

Sous définissabilité des occurrences `pre_k` concernées :

\[
\mathrm{Eval}(\rho,\iota,\omega,i,Shift_{\mathcal I}(\varphi)) = \mathrm{Eval}(\rho,\iota,\omega,i+1,\varphi).
\]

Ce lemme formalise précisément pourquoi les obligations de cohérence de la forme
\(Ante_t \Rightarrow Shift_{\mathcal I}(Req_u^u)\) relient bien un `ensure` courant à un `require` au pas suivant.

## 5. Règle statique `pre_k`

### Définition 5.1 - Distance minimale programme-seul

\[
d(s) = \min\{ i \mid \exists \rho,\; (s_i,\mu_i)\in \rho \land s_i=s\}
\]

(si \(s\) inatteignable, \(d(s)\) est non défini).

### Condition 5.2 - Validité des `pre_k` utilisateur

Pour toute transition \(t\) :

- pour chaque `pre_k(x,k)` dans \(Req_t^u\), exiger \(k \le d(src(t))\),
- pour chaque `pre_k(x,k)` dans \(Ens_t^u\), exiger \(k \le d(dst(t))\).

### Théorème 5.3 - Sûreté du check

Sous la condition 5.2, aucun `pre_k` utilisateur n'est évalué hors domaine.

Ce résultat constitue la base de \(L_{prek}\) pour la partie strictement utilisateur.

### Théorème-cible 5.4 - Couverture du check sur les obligations non-utilisateur

On note :

\[
AddedObl_{pre}(N^+) := \{\psi \in AddedObl(N^+) \mid OccPre(\psi)\neq\emptyset\}.
\]

On vise à établir :

\[
\forall \psi \in AddedObl_{pre}(N^+),\;
\forall pre_k(x,k)\in OccPre(\psi),\;
k \le Bound(\psi),
\]

où \(Bound(\psi)\) est la borne de distance utilisée au point d'évaluation de \(\psi\)
(programme-seul ou monitor-aware selon la variante).

Ici, \(OccPre(\psi)\) désigne l'ensemble des occurrences `pre_k` de \(\psi\).

### Lemme 5.5 - Résultat intermédiaire \(L_{prek}\)

Sous 5.2 et 5.4, aucune occurrence pertinente de `pre_k` (utilisateur ou ajoutée) n'est évaluée hors domaine dans les obligations utilisées par la preuve finale.

### Illustration sur D et T

- D : le `require` de `Run -> Run` contient `pre_k(x,1)` (donc `k=1`). La condition impose que `Run` soit atteignable à distance au moins 1.
- T : pas de `pre_k` utilisateur, le check passe trivialement.

## 6. Enrichissement OBC vers OBC+

### Définition 6.1 - Contrat enrichi par transition

On définit un noeud enrichi \(N^+\) avec les mêmes transitions d'exécution (éventuellement augmentées de code monitor), et des obligations ajoutées.

Pour une transition \(t\), contrat enrichi :

\[
Req_t^+ = Req_t^u \land Req_t^{compat} \land Req_t^{monpre} \land Req_t^{nobad}
\]
\[
Ens_t^+ = Ens_t^u \land Ens_t^{coh} \land Ens_t^{nobad} \land Ens_t^{smoke}
\]

avec \(Ens_t^{smoke}=true\) si le mode smoke est désactivé.

### Définition 6.2 - Obligation de cohérence ajoutée

Pour chaque transition \(t\), on prend :

\[
Ante_t =
\begin{cases}
\bigwedge Ens_t^u & \text{si } Ens_t^u \neq true\\
true & \text{sinon}
\end{cases}
\]

et, pour chaque transition \(u\) telle que \(src(u)=dst(t)\), on ajoute :

\[
Ante_t \Rightarrow Shift_{\mathcal I}(Req_u^u)
\]

Ceci correspond à la forme implémentée (pas de `InitGoals` séparé dans l'état actuel).

### Définition 6.3 - Ensemble des obligations ajoutées

\[
AddedObl(N^+) := \bigcup_{t\in T}
\{Req_t^{compat}, Req_t^{monpre}, Req_t^{nobad}, Ens_t^{coh}, Ens_t^{nobad}, Ens_t^{smoke}\}
\]

Partition utile pour la preuve :

\[
AddedObl(N^+) = AddedObl^{obj}(N^+) \cup AddedObl^{sup}(N^+)
\]

avec :

- \(AddedObl^{obj}(N^+)\) : obligations portant l'inatteignabilité de `bad` (`no bad state`),
- \(AddedObl^{sup}(N^+)\) : obligations de support (`Coherency`, `Compatibility`, `Monitor`, etc.).

Obligations totales :

\[
AllObl(N^+) = UserObl(N) \cup AddedObl(N^+)
\]

Remarque : `AddedObl` décrit les formules injectées dans les contrats enrichis. Les obligations
effectivement prouvées par le backend sont ensuite obtenues par génération WP/VC (section 10).

### Lemme 6.4 - Décomposition des obligations

Pour toute formule contractuelle enrichie de \(N^+\), on peut la classer en :

1. obligation utilisateur (`UserContract`) provenant de \(UserObl(N)\), ou
2. obligation ajoutée provenant de \(AddedObl(N^+)\).

Ce lemme permet de séparer la preuve en deux volets : correction utilisateur et correction des ajouts.

### Définition 6.5 - Correspondance avec les tags AST

Dans l'implémentation, les formules sont annotées par `origin` :

\[
origin \in \{UserContract, Coherency, Compatibility, Monitor, Internal\}
\]

Correspondance :

- `Coherency` : formules \(Ens_t^{coh}\).
- `Compatibility` : formules \(Req_t^{compat}\).
- `Monitor` : formules \(Req_t^{monpre}, Req_t^{nobad}, Ens_t^{nobad}\).
- `Internal` : \(Ens_t^{smoke}=false\) en mode smoke.
- `UserContract` : formules utilisateur conservées.

### Illustration pipeline sur D et T

- D : reçoit surtout des obligations `Coherency` liées au chaînage des `require/ensure`.
- T : reçoit principalement des obligations `Monitor/Compatibility` issues de la compilation des garanties LTL en contraintes monitor.

### 6.6 Vue phase par phase (OBC -> OBC+)

| Phase | Entrée -> Sortie | Ajouts principaux | Origines AST | Exemple D (`delay_int`) | Exemple T (`toggle`) |
|---|---|---|---|---|---|
| Parsing | Texte OBC -> AST OBC | Contrats utilisateur (`assume/guarantee`, `require/ensure`) | `UserContract` (quand renseigné) | `requires {prev}=pre_k(x,1)` sur `Run->Run` | Garanties LTL de bascule |
| Monitor generation | AST OBC -> automate monitor | États monitor, transitions monitor, atomes | (métadonnées de stage) | impact limité | automate non trivial à partir des garanties |
| Contracts pass (`contract_coherency`) | AST OBC + automate -> AST contracts | implications de cohérence dans `ensures` | `Coherency` | ajout de `Ante_t => Shift_I(req_succ)` | possible, mais souvent peu dominant |
| Monitor injection | AST contracts + automate -> AST monitor | `compat`, `monitor pre`, `no bad state`, code monitor | `Compatibility`, `Monitor` | ajout possible selon spec | ajout central (contrôle de la bascule via monitor) |
| Smoke (optionnel) | AST monitor -> AST monitor(smoke) | `ensure false` de diagnostic | `Internal` | détecte hypothèses incohérentes | idem |
| Backend Why3/OBC+ | AST final -> obligations backend | VCs + labels/provenance + rendu OBC+ | toutes | obligations cohérence + user | obligations monitor + user |

## 7. Opérateur \(Shift_{\mathcal I}\)

### Définition 7.1 - Action sur les historiques

Pour \(x\in \mathcal I\) :

\[
Shift_{\mathcal I}(Now(x)) = pre_k(x,1),\quad
Shift_{\mathcal I}(pre_k(x,k)) = pre_k(x,k+1)
\]

Pour \(x\notin \mathcal I\) :

\[
Shift_{\mathcal I}(Now(x)) = Now(x),\quad
Shift_{\mathcal I}(pre_k(x,k)) = pre_k(x,k)
\]

Extension homomorphe aux formules.

### Lemme 7.2 - Alignement temporel

Sous définissabilité, et par instanciation du lemme 4.10 :

\[
\mathrm{Eval}(\pi,i,Shift_{\mathcal I}(\varphi)) = \mathrm{Eval}(\pi,i+1,\varphi)
\]

Ce lemme est le coeur de \(L_{shift}\).

### Théorème 7.3 - Cohérence locale

Si \(t\) est exécutée au pas \(i\), et si son antécédent \(Ante_t\) est vrai, alors toute obligation ajoutée vers un successeur impose le `require` correspondant au pas \(i+1\).

Ce théorème instancie \(L_{coh}\) à partir de \(L_{shift}\).

## 8. Variante monitor-aware pour le check `pre_k`

### Définition 8.1 - Produit programme-monitor

Avec un automate monitor \(\mathcal M=(M,m_0,\Delta_M)\), on considère le produit \(S\times M\).

### Définition 8.2 - Distance monitor-aware

\[
d_M(s) = \min_{m\in M} d_P(s,m)
\]

avec \(d_P\) distance dans le produit.

### Condition 8.3 - Check raffiné

On remplace \(d\) par \(d_M\) dans la condition 5.2.

### Théorème 8.4 - Comparaison

\[
d(s) \le d_M(s)
\]

quand les deux sont définis.

Version sémantique filtrée (gardes monitor satisfaisables) :

\[
d_M(s) \le d_M^{sem}(s)
\]

Interprétation preuve : cette section fournit une borne plus précise pour établir \(L_{prek}\) quand le check `pre_k` est monitor-aware.

### Théorème-cible 8.5 - Adéquation monitor

On introduit deux prédicats sémantiques :

- \(ConsMon(\pi^+,\mathcal M)\) : la trace instrumentée est cohérente avec l'automate monitor
  (état monitor initial correct, valuation d'atomes correcte, et transitions monitor correctement suivies),
- \(NoBad(\pi^+,\mathcal M)\) : aucun pas de \(\pi^+\) n'atteint l'état `bad` du monitor.

On suppose la propriété de correction de la compilation monitor :

\[
MonCorr(\mathcal M,A,G):\quad
\forall \tau,\;
\big(ConsMon(\tau,\mathcal M)\land NoBad(\tau,\mathcal M)\land (\tau\downarrow_{\mathcal I}\models A)\big)
\Rightarrow
(\tau\models G).
\]

L'énoncé d'adéquation voulu est :

\[
\forall \pi^+ \text{ exécution de } N^+,\;
\Big(
(\pi^+\downarrow_{\mathcal I}\models A)
\land
\pi^+ \models Obl_{compat\cup mon}(N^+)
\land
MonCorr(\mathcal M,A,G)
\Big)
\Rightarrow
(\pi^+ \models G),
\]

où \(Obl_{compat\cup mon}(N^+)\) désigne la conjonction des obligations de provenance
`Compatibility` et `Monitor`, et où ces obligations impliquent :

\[
\pi^+ \models Obl_{compat\cup mon}(N^+)
\Rightarrow
\big(ConsMon(\pi^+,\mathcal M)\land NoBad(\pi^+,\mathcal M)\big).
\]

### Lemme 8.6 - Résultat intermédiaire \(L_{mon}\)

Sous 8.5, la validité des obligations `Compatibility` et `Monitor` est suffisante pour relier l'hypothèse d'entrée \(A\) et la garantie \(G\) sur \(N^+\), via \(ConsMon\), \(NoBad\) et \(MonCorr\).

## 9. Projection sémantique OBC+/OBC

### Définition 9.1 - Projection

Une exécution de \(N^+\) peut contenir des composantes auxiliaires (exemple : état monitor).
On note \(\pi^+\downarrow N\) la projection qui oublie ces composantes.

### Hypothèses 9.2 - Conditions de préservation

On suppose :

1. l'instrumentation n'altère pas les affectations des variables observables de \(N\) (hors variables auxiliaires),
2. les gardes et la structure de contrôle de \(N\) sont préservées sur la projection,
3. les obligations ajoutées (`Coherency`, `Compatibility`, `Monitor`, `Internal`) n'introduisent pas d'effet de bord opérationnel sur l'état observable.

### Lemme 9.3 - Préservation des exécutions (OBC+ -> OBC)

Sous 9.2 :

\[
\forall \pi^+ \text{ exécution de } N^+,\; \pi^+\downarrow N \text{ est une exécution de } N
\]

C'est exactement \(L_{proj}\).

### Preuve 9.4

Preuve détaillée donnée en section 12.9.

## 10. Génération des obligations (WP/Why3)

### Définition 10.1 - Transformateur `wp`

On introduit un transformateur :

\[
wp(stmt,Q)
\]

où \(stmt\) est un corps de transition et \(Q\) une post-condition.

### Théorème 10.2 - Correction de `wp` (soundness)

Pour toute formule \(P\), tout statement \(stmt\), toute post-condition \(Q\) :

\[
\models P \Rightarrow wp(stmt,Q)
\Longrightarrow
\{P\}\ stmt\ \{Q\}.
\]

### Définition 10.3 - Générateur d'obligations

Pour chaque transition \(t\), avec contrat enrichi \((Req_t^+,Ens_t^+)\), on définit :

\[
VC_t(N^+) := \{\, Req_t^+ \Rightarrow wp(body_t,Ens_t^+) \,\}.
\]

Le générateur global est :

\[
VCGen(N^+) := \bigcup_{t\in T} VC_t(N^+) \cup VC_{node}(N^+),
\]

où \(VC_{node}(N^+)\) regroupe les obligations de niveau noeud (liens assume/guarantee,
monitor, invariants globaux éventuels).

### Théorème 10.4 - Correction de `VCGen` (soundness backend)

\[
\Big(\forall vc \in VCGen(N^+),\; \models vc\Big)
\Longrightarrow
\Big(\forall t\in T,\; \{Req_t^+\}\ body_t\ \{Ens_t^+\}\Big)
\land
\text{les obligations de }VC_{node}(N^+) \text{ sont satisfaites.}
\]

## 11. Théorème global de correction

### Hypothèses/Lemmes requis 11.1

1. \(L_{prek}\) : lemme 5.5 (éventuellement raffiné monitor-aware via section 8).
2. Validité de toutes les VCs générées :

\[
\forall vc \in VCGen(N^+),\; \models vc
\]

3. \(L_{mon}\) : lemme 8.6 (adéquation monitor).
4. \(L_{proj}\) : lemme de préservation 9.3.
5. Mode normal pour le théorème fonctionnel (smoke désactivé).
6. Correction de `VCGen` : théorème 10.4.
7. Lecture objectif/support de 6.3 :
   les obligations de support \(AddedObl^{sup}\) sont celles utilisées pour établir
   les obligations objectif \(AddedObl^{obj}\) (`NoBad`).

### Théorème 11.2 - Bout en bout

Sous 11.1,

\[
\forall \pi \text{ exécution de } N,\quad (\pi\downarrow_{\mathcal I} \models A) \Rightarrow (\pi \models G)
\]

### Preuve 11.3

Preuve détaillée donnée en section 12.11.

## 12. Preuves détaillées

Cette section ferme explicitement toute la chaîne
\(L_{prek}\land L_{shift}\land L_{coh}\land L_{mon}\land L_{proj}\Rightarrow T_{final}\),
sous les hypothèses énoncées aux sections 5, 8, 9, 10 et 11.

### 12.1 Preuve du lemme 4.10 (sens du `Shift`)

On raisonne par induction structurelle sur \(\varphi\).

Cas de base :

1. \(\varphi = Now(x)\).
   - Si \(x\in\mathcal I\), par définition 7.1 :
     \(Shift_{\mathcal I}(Now(x))=pre_k(x,1)\).
     Alors
     \(\mathrm{Eval}(\rho,\iota,\omega,i,Shift_{\mathcal I}(Now(x)))
     =\mathrm{Eval}(\rho,\iota,\omega,i,pre_k(x,1))
     =\mathrm{Eval}(\rho,\iota,\omega,i+1,Now(x))\)
     (définition 4.7, sous définissabilité).
   - Si \(x\notin\mathcal I\), \(Shift_{\mathcal I}(Now(x))=Now(x)\), donc l'égalité est immédiate.
2. \(\varphi = pre_k(x,k)\) :
   - si \(x\in\mathcal I\), \(Shift_{\mathcal I}(pre_k(x,k))=pre_k(x,k+1)\),
     et l'égalité découle de 4.7 ;
   - sinon, \(Shift_{\mathcal I}(pre_k(x,k))=pre_k(x,k)\), égalité immédiate.

Cas inductifs :

Les connecteurs booléens/FO/LTL sont traités homomorphiquement (7.1), donc
l'hypothèse d'induction sur les sous-formules se propage directement à la formule entière.

Conclusion : le lemme 4.10 est prouvé.

### 12.2 Preuve du théorème 5.3 (sûreté du check utilisateur)

Soit une transition \(t\) exécutée au pas \(i\).

1. Pour toute occurrence `pre_k(x,k)` dans \(Req_t^u\), 5.2 impose \(k\le d(src(t))\).
   Comme \(t\) est exécutée à \(i\), l'état \(src(t)\) est atteint à \(i\), donc \(i\ge d(src(t))\), donc \(i\ge k\).
   Par 4.7, l'occurrence est définie au point d'évaluation `require`.
2. Pour toute occurrence `pre_k(x,k)` dans \(Ens_t^u\), 5.2 impose \(k\le d(dst(t))\).
   À l'exécution de \(t\), le post-état est au pas \(i+1\) avec état \(dst(t)\), donc \(i+1\ge d(dst(t))\), donc \(i+1\ge k\).
   Par 4.7, l'occurrence est définie au point d'évaluation `ensure`.

Donc aucune occurrence `pre_k` utilisateur n'est évaluée hors domaine.

### 12.3 Preuve du lemme 5.5 (\(L_{prek}\))

Par 12.2, toutes les occurrences `pre_k` des obligations utilisateur sont définies.
Par le théorème-cible 5.4, la même propriété vaut pour \(AddedObl_{pre}(N^+)\).
Par union des deux ensembles d'obligations pertinentes, toute occurrence utilisée dans la preuve finale est définie.

### 12.4 Preuve du lemme 6.4 (décomposition)

Par construction (sections 6.1, 6.3, 6.5), chaque formule contractuelle enrichie est :

1. soit préexistante (origine utilisateur),
2. soit injectée par une passe d'enrichissement (`Coherency`, `Compatibility`, `Monitor`, `Internal`).

Ces catégories sont disjointes au niveau origine et couvrent toutes les formules enrichies.
La décomposition est donc immédiate.

### 12.5 Preuve du théorème 7.3 (\(L_{coh}\))

Soit \(t\) exécutée au pas \(i\), et \(u\) telle que \(src(u)=dst(t)\).
Par 6.2, l'obligation
\(Ante_t \Rightarrow Shift_{\mathcal I}(Req_u^u)\)
est ajoutée au contrat enrichi.
Si \(Ante_t\) est vraie au pas \(i\), on obtient
\(Shift_{\mathcal I}(Req_u^u)\) vraie au pas \(i\).
Par 12.1 (lemme 4.10), cela équivaut à \(Req_u^u\) vraie au pas \(i+1\).
Donc le `require` successeur est bien propagé.

### 12.6 Preuve du théorème 8.4 (comparaison des bornes)

1. Toute exécution du produit programme-monitor se projette sur une exécution programme
   (on oublie la composante monitor).
2. Si \((s,m)\) est atteignable au pas \(i\) dans le produit, alors \(s\) est atteignable au pas \(i\) dans le programme.
3. Donc, en prenant les minima, \(d(s)\le d_M(s)\).
4. Le produit sémantique retire des arêtes au produit structurel ; il ne peut donc qu'augmenter (ou laisser égales) les distances minimales : \(d_M(s)\le d_M^{sem}(s)\).

### 12.7 Preuve du théorème-cible 8.5 (adéquation monitor)

On fixe une exécution \(\pi^+\) de \(N^+\) telle que :

1. \(\pi^+\downarrow_{\mathcal I}\models A\),
2. \(\pi^+ \models Obl_{compat\cup mon}(N^+)\),
3. \(MonCorr(\mathcal M,A,G)\).

On note \(m_i\) l'état monitor au pas \(i\) (composante instrumentée de \(\pi^+\)).
Par l'hypothèse structurelle associée à 8.5
\(\big(\pi^+\models Obl_{compat\cup mon}(N^+) \Rightarrow ConsMon(\pi^+,\mathcal M)\land NoBad(\pi^+,\mathcal M)\big)\),
l'hypothèse 2 donne :

\[
ConsMon(\pi^+,\mathcal M)\land NoBad(\pi^+,\mathcal M).
\]

On explicite ensuite les composantes de cette conjonction :

1. (`compat`) **cohérence état monitor / valuation d'atomes** :
   la valuation des atomes LTL au pas \(i\) correspond à l'interprétation sémantique associée à \(m_i\),
2. (`monitor pre/post`) **respect de la transition monitor** :
   si \(m_i\) est l'état courant et les atomes satisfont la garde \(g\), alors \(m_{i+1}\) est un successeur autorisé,
3. (`no bad state`) **exclusion de l'état mauvais** :
   \(m_i \neq bad\) pour tout \(i\).

On raisonne par induction sur \(i\).

Base \(i=0\) :

- par initialisation instrumentée, \(m_0\) est l'état initial du monitor,
- par 1., la sémantique des atomes est cohérente dès \(0\),
- par 3., \(m_0\neq bad\).

Hérédité :

- hypothèse d'induction : \(m_i\) est cohérent (1.) et non `bad`,
- par 2., la transition \(m_i\to m_{i+1}\) suit la sémantique monitor,
- par 3., \(m_{i+1}\neq bad\),
- donc la cohérence logique est préservée au pas \(i+1\).

Par l'hypothèse 3 (`MonCorr`), combinée avec
\(ConsMon(\pi^+,\mathcal M)\), \(NoBad(\pi^+,\mathcal M)\) et 1.,
on conclut \(\pi^+\models G\).
Donc \(\pi^+\models G\).

Le théorème-cible 8.5 est prouvé.

### 12.8 Preuve du lemme 8.6 (\(L_{mon}\))

Le lemme 8.6 est une conséquence immédiate de 12.7 : l'énoncé de 8.6 est exactement
la conclusion utile de 8.5 dans la chaîne de preuve globale.

### 12.9 Preuve du lemme 9.3 (\(L_{proj}\))

Soit \(\pi^+\) une exécution de \(N^+\).

1. Par 9.2.1, les mises à jour des variables observables sont identiques à celles du programme source.
2. Par 9.2.2, chaque pas de contrôle projeté correspond à un pas valide de \(N\).
3. Par 9.2.3, les obligations ajoutées n'introduisent pas de dynamique opérationnelle observable.

Donc la projection \(\pi^+\downarrow N\) satisfait la relation de transition de \(N\) à chaque pas ;
c'est donc une exécution de \(N\).

### 12.10 Preuve du théorème 10.4 (correction `VCGen`)

1. Pour un \(t\) fixé, si \(Req_t^+ \Rightarrow wp(body_t,Ens_t^+)\) est valide, alors par 10.2
   le triple \(\{Req_t^+\}\ body_t\ \{Ens_t^+\}\) est valide.
2. En appliquant 1 à tout \(t\in T\), on obtient
   \(\forall t,\{Req_t^+\}\ body_t\ \{Ens_t^+\}\).
3. Les obligations de \(VC_{node}(N^+)\) étant incluses dans \(VCGen(N^+)\),
   leur validité découle de \(\forall vc\in VCGen(N^+),\models vc\).

La conclusion de 10.4 suit.

### 12.11 Preuve du théorème 11.2 (bout en bout)

Soit \(\pi\) une exécution de \(N\) telle que \(\pi\downarrow_{\mathcal I}\models A\).

1. Par 6.4, les obligations se décomposent en composante utilisateur et composante ajoutée.
2. Par 11.1(7), on sépare \(AddedObl\) en obligations objectif (`NoBad`) et obligations de support.
3. Par 12.3 (\(L_{prek}\)), toutes les occurrences `pre_k` nécessaires aux obligations sont bien définies.
4. Par 12.5 (\(L_{coh}\)) et les obligations de support, la chaîne temporelle des `require/ensure` est correcte.
5. Par 12.10 et 11.1(2), les VCs Why3 valides impliquent la validité sémantique des obligations (support puis objectif).
6. En particulier, les obligations objectif (`NoBad`) sont satisfaites.
7. Par 12.7 (\(L_{mon}\)) et `MonCorr`, `NoBad` sous \(A\) implique \(G\) sur \(N^+\).
8. Par 12.9 (\(L_{proj}\)), tout raisonnement fait sur \(N^+\) se projette en raisonnement valide sur \(N\).

Donc \((\pi\downarrow_{\mathcal I}\models A)\Rightarrow(\pi\models G)\).

## 13. Synthèse des deux exemples

- D (`delay_int`) illustre principalement : `pre_k`, `Shift_{\mathcal I}`, et `Coherency`.
- T (`toggle`) illustre principalement : obligations monitor et compatibilité pour relier les garanties LTL à la sémantique transitionnelle.

Les deux exemples ensemble couvrent les étapes essentielles du pipeline OBC \(\to\) OBC+.
