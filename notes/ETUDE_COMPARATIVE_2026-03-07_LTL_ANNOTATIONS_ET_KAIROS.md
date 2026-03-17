# Etude comparative: article LTL par generation d'annotations vs architecture Kairos

## 1. Source et perimetre

Article etudie:
- Nicolas Stouls, Julien Groslambert,
  `Verification de proprietes LTL sur des programmes C par generation d'annotations`
  (Inria, 2011), fourni sous la forme
  `/Users/fredericdabrowski/Desktop/main.pdf`.

Projet compare:
- Kairos, branche `codex/refactoring-architecture-rocq`, avec:
  - noyau Rocq de correction automate,
  - produit explicite `programme x A x G`,
  - obligations locales,
  - projection vers backend OCaml / Why3.

Limite de lecture:
- le PDF fourni s'extrait partiellement mal a cause de l'encodage des fontes;
  l'etude ci-dessous s'appuie sur:
  - le titre et les metadonnees du PDF,
  - les pages et formules lisibles de la partie centrale,
  - en particulier les definitions autour d'un automate
    `A = <Q, q0, R>`, de la synchronisation `sync(A, sigma, i)`, et de la
    decomposition des annotations en `DeclA`, `TransA`, `SyncA`.

Cette base est suffisante pour comparer l'idee centrale de l'article a Kairos:
compiler une specification temporelle en automate, synchroniser cet automate avec
l'execution, puis generer des obligations/annotations locales qu'un outil externe
doit valider.

Point de prudence important:
- l'article semble raisonner sur des observations de programme de type etats,
  appels/retours ou predicats de controle instrumentes;
- Kairos, lui, raisonne explicitement sur des traces reactives d'execution
  entree/sortie, enrichies par la memoire et l'historique.

La comparaison qui suit porte donc sur une meme famille de methodes, mais pas
sur deux objets semantiques strictement identiques.

## 2. Resume technique de l'article

L'article semble suivre la chaine conceptuelle suivante:

1. une propriete LTL sur un programme C est compilee en automate;
2. l'execution du programme est vue comme un mot ou une suite d'etats observables,
   vraisemblablement proches d'une trace de controle instrumentee;
3. on synchronise l'automate avec cette execution via une fonction de type
   `sync(A, sigma, i)`, qui represente l'ensemble des etats automates compatibles
   avec le prefixe courant;
4. on genere ensuite des annotations locales sur le programme:
   - declarations de variables logiques pour representer les etats automates,
   - equations / contraintes de transition entre ces variables,
   - invariants de synchronisation reliant le programme et l'automate;
5. la preuve de la propriete est alors devolue a la validation de ces annotations
   par un backend de verification.

L'idee cle est donc:
- transformer une propriete temporelle globale en un nombre fini de contraintes
  locales sur des points de programme;
- faire porter l'essentiel de l'automatisation sur la generation des annotations,
  pas sur une preuve temporelle globale faite directement par le backend.

## 2bis. Methode de l'article, reconstruite plus finement

Cette section detaille autant que possible la methode de l'article a partir des
elements effectivement lisibles dans le PDF.

### 2bis.1. Pipeline outille visible

Une figure lisible du PDF montre explicitement une chaine du type:

1. formule `LTL`,
2. traduction `LTL2BA`,
3. `automate de Büchi simplifiée`,
4. `calcul des annotations`,
5. `pré-traitement Frama-C`,
6. `programme C annoté`,
7. `Jessie pour Frama-C`,
8. `Why`,
9. `prouveurs`.

On peut donc affirmer avec un bon niveau de confiance que leur methode n'est pas
un simple monitorage externe:
- la propriete est compilee;
- les annotations sont injectees dans le programme C;
- puis une vraie chaine de verification deductive est lancee.

### 2bis.2. Nature de l'automate manipule

Le PDF laisse lire une presentation d'un automate sous la forme:
\[
A = \langle Q, q_0, R \rangle
\]
avec:
- \(Q\) ensemble d'etats;
- \(q_0 \in Q\) etat initial;
- \(R \subseteq Q \times PRED \times Q\) relation de transition etiquetee par
  des predicats.

Le fait que les transitions soient etiquetees par `PRED` est important:
- l'automate ne semble pas lire directement des evenements purs;
- il lit plutot des predicats evaluables sur les etats observables du programme.

Cela confirme que la methode travaille bien sur une execution du programme
instrumentee par des predicates de programme, et pas sur une simple liste brute
d'appels.

### 2bis.3. Synchronisation automate / execution

Le PDF donne explicitement une fonction:
\[
\mathrm{sync} : BUCHI \times PATH \times \Nat \to 2^Q.
\]

Les clauses lisibles sont du style:
\[
\mathrm{sync}(A,\sigma,0)=\{q_0\}
\]
et, pour \(i>0\), \(\mathrm{sync}(A,\sigma,i)\) contient les etats \(q'\) tels
qu'il existe:
- un predicat \(P \in PRED\),
- un etat precedent \(q \in Q\),

avec:
- \(\sigma(i-1) \models P\),
- \(q \in \mathrm{sync}(A,\sigma,i-1)\),
- \(\langle q,P,q' \rangle \in R\).

La lecture la plus plausible est donc:
- \(\sigma\) est une execution ou une trace du programme;
- \(\mathrm{sync}(A,\sigma,i)\) est l'ensemble des etats automates compatibles
  avec le prefixe de longueur \(i\);
- la mise a jour de cet ensemble est calculee par propagation des transitions
  dont les etiquettes predicatives sont vraies sur l'etat courant de la trace.

On voit aussi apparaitre une condition `CSync` du type:
\[
\forall i,\ \mathrm{sync}(A,\sigma,i) \neq \varnothing.
\]

Intuitivement:
- cette condition exprime que l'execution reste compatible avec l'automate;
- elle joue le role d'un invariant global de synchronisation entre programme et
  propriete.

### 2bis.4. Generation d'annotations

Le PDF laisse lire une decomposition:
\[
Ann_A = Decl_A \cup Trans_A \cup Sync_A.
\]

La signification la plus plausible est:

- `DeclA`:
  declarations des variables logiques/ghost necessaires pour representer les
  etats automates;
- `TransA`:
  contraintes de transition qui expriment comment ces variables evoluent d'un
  point de programme au suivant;
- `SyncA`:
  contraintes globales de synchronisation, en particulier le fait que l'etat
  d'automate represente reste non vide / coherent le long de la trace.

Des fragments lisibles suggerent aussi des variables booleennes indexees par les
etats \(q \in Q\), de la forme \(v_q\), avec:
- initialisation de \(v_{q_0}\) a vrai;
- equations de transition reconstruisant les \(v_q\) au pas suivant.

Donc la methode concrete semble etre:

1. associer a chaque etat d'automate une variable logique dans le programme;
2. initialiser ces variables selon \(q_0\);
3. injecter des formules exprimant la propagation des etats possibles;
4. ajouter un invariant de non-vacuite / synchronisation;
5. demander au backend deductif de prouver que ces annotations tiennent.

### 2bis.5. Role exact de la verification deductive

Cette reconstruction permet de repondre a une question importante:
- l'article ne fait pas un simple suivi a posteriori des appels;
- il fait bien de la verification deductive sur le programme annote.

Mais cette verification deductive semble porter sur un but precis:
- prouver que les variables/annotations representant l'automate evoluent
  correctement le long de l'execution du programme.

Autrement dit, la deduction sert a valider un \emph{encodage de synchronisation}
entre programme et automate.

Ce n'est pas encore la meme chose que:
- construire un produit semantique explicite,
- le parcourir comme IR central,
- puis prouver en interne des lemmes de couverture locale comme Kairos le fait.

### 2bis.6. Exemples visibles dans le PDF

Le texte extrait laisse voir des exemples utilisant des observables comme:
- `Call(init_trans)`,
- `Return(init_trans)`,
- `Call(commit_trans)`,
- des variables de programme comme `status` ou `cpt`.

Cela renforce l'interpretation suivante:
- les proprietes verifiees portent sur des traces instrumentees melant
  evenements de controle et predicats sur les variables du programme;
- on n'est pas, au moins dans les exemples visibles, dans un cadre de traces
  reactives entree/sortie explicites comme dans Kairos.

## 2ter. Resultats obtenus par l'article

### 2ter.1. Resultat methodologique principal

Le resultat principal de l'article semble etre d'ordre methodologique:
- montrer qu'une propriete LTL sur un programme C peut etre traduite en un
  ensemble fini d'annotations locales;
- puis que ces annotations peuvent etre traitees par une chaine deductive
  existante (`Frama-C` / `Jessie` / `Why` / prouveurs SMT).

Le gain revendique n'est donc pas seulement de ``surveiller'' la propriete, mais
de la ramener dans un cadre de verification deductive classique.

### 2ter.2. Resultat semantique visible

Ce que la partie lisible permet d'attribuer avec confiance a l'article est:
- une condition de synchronisation `sync(A,\sigma,i)` explicite;
- une decomposition des annotations en declaration / transition /
  synchronisation;
- une preuve ou au moins une verification outillee du fait que ces annotations
  suffisent pour relier la propriete LTL au programme annote.

En revanche, sur la seule base du PDF partiellement extrait, il serait excessif
d'affirmer:
- un theoreme mechanise complet de correction de bout en bout;
- ou une preuve interne du style
  `violation globale -> contre-exemple local -> annotation violee`.

L'article semble plutot etablir que \emph{si les annotations generees sont
prouvees, alors la propriete LTL est capturee correctement}.

### 2ter.3. Portee pratique des exemples

Les exemples lisibles suggerent que la methode sait exprimer des proprietes sur:
- des protocoles de transactions ou d'appels de fonctions;
- des variables de controle entieres/booleennes;
- des contraintes temporelles portant sur l'ordre des appels et certains etats.

Cela donne une portee pratique reelle, mais sur un objet qui reste apparemment
plus proche du programme annote que d'un systeme reactif entree/sortie complet.

## 3. Resume technique de Kairos

Kairos, dans son architecture actuelle, suit la chaine suivante:

1. le programme est modele comme un automate de controle avec memoire;
2. une specification d'entree est modelisee par un automate d'hypothese `A`;
3. une specification de surete sur la trace reactive entree/sortie est modelisee
   par un automate de garantie `G`;
4. on construit un produit explicite
   `programme x A x G`;
5. chaque tick realise un pas local du produit, qui porte:
   - la transition programme,
   - l'arete suivie dans `A`,
   - l'arete suivie dans `G`;
6. les pas dont la cible met `G` dans `bad_G` sont classes comme dangereux;
7. a partir de ces pas, on genere des obligations locales;
8. la preuve Rocq interne montre:
   - progression du produit,
   - `violation globale de G -> pas local dangereux`,
   - `pas local dangereux -> obligation generee violee`;
9. la fermeture finale depend d'un oracle externe suppose sound et complete sur les
   obligations generees.

Les points de reference principaux sont:
- [KairosOracle.v](/Users/fredericdabrowski/Repos/kairos/rocq/KairosOracle.v)
- [AutomataCorrectnessCore.v](/Users/fredericdabrowski/Repos/kairos/rocq/core/AutomataCorrectnessCore.v)
- [ThreeLayerFromCore.v](/Users/fredericdabrowski/Repos/kairos/rocq/integration/ThreeLayerFromCore.v)
- [ExternalValidationAssumptions.v](/Users/fredericdabrowski/Repos/kairos/rocq/interfaces/ExternalValidationAssumptions.v)
- [AutomataFinalCorrectness.v](/Users/fredericdabrowski/Repos/kairos/rocq/integration/AutomataFinalCorrectness.v)
- [rocq_oracle_model.tex](/Users/fredericdabrowski/Repos/kairos/spec/rocq_oracle_model.tex)

## 4. Convergence de fond

### 4.1. Meme idee directrice

Le point commun le plus fort est le suivant:
- dans les deux cas, une propriete temporelle globale n'est pas envoyee telle
  quelle au backend;
- elle est d'abord compilee en un artefact fini de type automate;
- puis cet automate est synchronise avec l'execution concrete;
- enfin on ne demande au backend externe que de valider des contraintes locales.

Autrement dit, Kairos et l'article partagent la meme intuition structurante:
`temps global -> automate fini -> obligations locales`.

Mais cette convergence reste une convergence de \emph{methode}, pas d'objet
semantique complet:
- article: trace instrumentee de programme C;
- Kairos: trace reactive entree/sortie et specification assume/guarantee.

### 4.2. Meme reduction du global au local

Dans l'article:
- une formule LTL sur des executions C devient un ensemble d'annotations locales
  sur les etats / transitions du programme.

Dans Kairos:
- `~AvoidG` est reduit a l'existence d'un tick local problematique;
- ce tick est reduit a un pas produit dangereux;
- ce pas est reduit a une obligation locale falsifiee.

La parenté intellectuelle est forte. Kairos est clairement dans la meme famille
que l'approche de l'article, mais avec une decomposition de preuve beaucoup plus
explicite.

### 4.3. Meme dependance a un backend externe

Dans les deux cas, il existe une frontiere externe:
- article: validite des annotations generees;
- Kairos: soundness et completeness de l'oracle sur les obligations generees.

La difference n'est pas de nature mais de presentation:
- l'article met plutot en avant la generation d'annotations;
- Kairos met en avant la notion d'obligation abstraite et isole proprement la
  validation externe dans une interface Rocq.

## 5. Differences structurantes

### 5.1. Article: programme C annote ; Kairos: semantique reactive explicite

L'article prend pour objet un programme C existant, sur lequel on ajoute des
annotations pour exprimer des contraintes temporelles compilees.

Kairos fait un choix plus semantique:
- il fixe explicitement une semantique reactive du programme;
- il introduit un produit `programme x A x G` comme objet mathematique central;
- il prouve en Rocq les lemmes reliant ce produit a la correction.

Conséquence:
- l'article est plus directement oriente ``verification d'un code existant'';
- Kairos est plus proche d'une architecture de preuve et de compilation semantique.

### 5.2. Article: traces de controle/programme ; Kairos: traces reactives d'execution

L'article semble observer le programme au travers de predicats d'etat, d'appels,
de retours, ou plus generalement d'une instrumentation de la trace du programme C.

Kairos vise un objet semantique plus riche:
- une entree courante `i(k)`,
- une sortie courante `o(k)`,
- un etat de controle,
- une memoire,
- et, si besoin, un historique interprete via `prev`, variables retardees ou
  memoire programme.

Autrement dit:
- l'article semble verifier des proprietes LTL sur une trace de programme;
- Kairos verifie des proprietes de surete sur la trace d'execution reactive elle-meme.

C'est une difference de fond. Kairos n'est pas seulement plus modulaire; il
travaille aussi sur un objet observe plus proche de la semantique du systeme.

### 5.3. Article: synchronisation automate / execution ; Kairos: produit complet

L'article semble maintenir des variables ou ensembles d'etats automates
compatibles avec le prefixe courant (`sync(A, sigma, i)`).

Kairos va plus loin en faisant du triplet
`(etat programme, etat A, etat G)` l'objet canonique.

Avantage Kairos:
- la progression du produit est un lemme prouve, pas un mecanisme implicite;
- les obligations sont attachees a un pas `programme x A x G` precis;
- la non-atteinte de `bad_G` devient une propriete geometrique du produit.

Autrement dit, l'article synchronise un automate avec le programme; Kairos
internalise cette synchronisation sous forme de produit explicite.

### 5.4. Article: une propriete ; Kairos: specification d'entree + garantie

L'asymetrie la plus importante est ici:
- l'article semble partir d'une propriete LTL a verifier sur un programme;
- Kairos part d'une \emph{specification d'entree} explicite `A` et d'une
  \emph{specification de garantie} explicite `G`.

La correction visee par Kairos n'est donc pas simplement:
- ``le programme satisfait telle formule temporelle'',

mais:
\[
\mathrm{AvoidA}(u) \Rightarrow \mathrm{AvoidG}(\mathrm{run}(u)).
\]

Cela signifie:
- toutes les entrees ne sont pas mises sur le meme plan;
- les executions non admissibles selon `A` sont filtrees semantiquement;
- le produit suit explicitement les deux dimensions: admissibilite de l'entree et
  conformite de la garantie.

L'article ne semble pas offrir, au moins dans son axe principal, une separation
de meme niveau entre specification d'entree et specification de sortie.

### 5.5. Article: orientation LTL generale ; Kairos: surete + hypothese/garantie

L'article part d'une propriete LTL generale sur un programme C.

Kairos travaille plus specifiquement avec:
- un automate d'hypothese `A`,
- un automate de garantie `G`,
- une correction conditionnelle `AvoidA -> AvoidG`.

Kairos introduit donc explicitement une logique assume/guarantee que l'article,
au moins dans son axe principal, ne semble pas structurer de cette facon.

Cette difference est importante:
- l'article traite d'abord la compilation d'une propriete;
- Kairos traite aussi la separation entre comportement admissible d'entree et
  comportement garanti de sortie.

### 5.6. Kairos prouve le noyau interne, pas seulement la projection

Le resultat probablement le plus important de Kairos par rapport a l'article est
celui-ci:
- l'article motive une generation correcte d'annotations;
- Kairos prouve explicitement en Rocq le noyau
  `violation globale -> pas dangereux local -> obligation generee violee`.

Cela signifie que Kairos n'est pas seulement une technique de reduction pratique;
c'est une reduction prouvee dans le noyau.

## 6. Correspondance fine des objets

### 6.1. Automate de propriete de l'article vs automates `A` / `G` de Kairos

Dans l'article:
- un automate compile une formule LTL;
- les etats de cet automate sont suivis via annotations.

Dans Kairos:
- `G` joue exactement ce role pour la garantie;
- `A` ajoute un second automate, non pas pour surveiller la garantie, mais pour
  filtrer les executions admissibles.

Donc la correspondance la plus proche est:
- automate LTL de l'article <-> automate `G` de Kairos;
- il n'y a pas d'analogue aussi explicite de `A` dans la ligne principale de l'article,
  alors que `A` est central dans Kairos.

### 6.2. `sync(A, sigma, i)` vs `rps(u,k)`

La notion lisible `sync(A, sigma, i)` de l'article sert a relier:
- un prefixe d'execution,
- un ensemble d'etats automates compatibles.

Dans Kairos, l'analogue est plus fort:
\[
\mathrm{rps}(u,k) = (s_u(k), q_A(k), q_G(k)).
\]

Ce n'est pas seulement un ensemble d'etats compatibles, mais l'etat concret du
produit au tick `k`.

Avantage:
- Kairos supprime une partie du flottement entre ``etats possibles'' et
  ``etat effectivement realise''.

### 6.3. Annotations `DeclA / TransA / SyncA` vs familles d'obligations Kairos

Les constructions lisibles du PDF de l'article sont:
- `DeclA`: declarations de variables d'etat automate,
- `TransA`: contraintes de transition,
- `SyncA`: invariants de synchronisation.

La decomposition Kairos la plus proche est:
- `ObjectiveNoBad` / `FamNoBad*`:
  contraintes qui interdisent les pas menant a `bad_G`;
- `CoherencyGoal` / `FamCoherency*`:
  contraintes de coherence entre etat abstrait et encodage backend;
- `SupportAutomaton` / `FamMonitorCompatibilityRequires`,
  `FamStateAwareAssumptionRequires`:
  contraintes de support pour que l'exploitation des automates soit correcte;
- `SupportUserInvariant` / `FamTransition*`:
  obligations deja attachees au programme.

Le parallelisme est tres net:
- `DeclA/SyncA` de l'article ressemblent aux obligations de coherence/support;
- `TransA` ressemble aux obligations portees par les transitions dans Kairos;
- Kairos ajoute une taxonomie plus fine entre objectif, coherence et support.

## 7. Ce que Kairos fait mieux

### 7.1. Separation du noyau prouve et des hypotheses externes

L'un des apports majeurs de Kairos est architectural:
- le noyau de reduction locale est prouve en Rocq;
- les hypotheses externes sont isolees dans
  [ExternalValidationAssumptions.v](/Users/fredericdabrowski/Repos/kairos/rocq/interfaces/ExternalValidationAssumptions.v).

Cette frontiere est beaucoup plus nette que dans une presentation classique de
generation d'annotations, ou le backend externe et la reduction interne sont
souvent presentes comme un seul bloc methodologique.

### 7.2. Produit explicite et progression non bloquante

Kairos prouve aussi quelque chose que l'article ne met pas au centre:
- a chaque tick, il existe un pas produit realisable et bien forme;
- donc le produit progresse explicitement.

Cela traite directement la question du non-blocage du produit, qui est critique
des qu'on fait reposer la correction sur des pas locaux.

### 7.3. Taxonomie explicite des obligations

L'article semble distinguer des familles d'annotations par fonction
(declaration, transition, synchronisation).

Kairos pousse cette idee plus loin en explicitant:
- le role logique d'une obligation,
- sa provenance,
- puis sa famille backend.

Cette stratification est superieure pour un projet qui veut:
- raisonner modularite,
- changer de backend,
- ou maintenir une preuve Rocq stable face aux refactorings d'implementation.

## 8. Ce que l'article suggere encore utilement a Kairos

### 8.1. Presentation plus algorithmique de l'extraction

L'article met vraisemblablement davantage l'accent sur l'algorithme:
- compiler la formule,
- calculer les etats synchronises,
- injecter les annotations.

Kairos, lui, est aujourd'hui plus fort sur le noyau semantique et la preuve,
mais parfois moins immediat sur la presentation operative de ``comment on passe
de la spec a la formule backend''.

Cela confirme que la documentation Kairos gagne a:
- expliciter encore davantage les operateurs d'extraction,
- montrer leur projection concrete vers Why3/OBC,
- et donner des schemas de generation plus algorithmiques.

### 8.2. Notation de synchronisation compacte

La notation `sync(A, sigma, i)` de l'article a une vertu pedagogique:
- elle donne une image immediate de la progression de l'automate le long d'une execution.

Kairos a fait le choix plus robuste du produit explicite, mais pourrait encore
beneficier d'une notation derivee compacte pour:
- decrire intuitivement la projection de `G`,
- expliquer le backend,
- ou presenter les etats atteignables avant d'introduire tout le triplet.

### 8.3. Axe ``generation d'annotations'' plus visible

Le vocabulaire de l'article insiste sur la \emph{generation d'annotations}.
Pour Kairos, c'est utile parce que:
- du point de vue utilisateur/outil, ce qu'on voit est encore largement une
  generation de formules backend;
- le fait que ces formules viennent d'un produit prouve en Rocq doit rester
  visible, mais ne doit pas masquer le pipeline concret.

En d'autres termes:
- Kairos a une meilleure theorie;
- l'article rappelle qu'il faut aussi raconter clairement l'histoire de la
  compilation concrete vers les annotations.

## 9. Ce que l'article ne couvre pas assez pour Kairos

### 9.1. Hypotheses/garanties separees

Le cadre `A/G` de Kairos est plus riche qu'une simple propriete LTL compilee:
- on veut raisonner sous hypothese d'entree;
- on veut isoler les executions non admissibles;
- on veut separer nettement `bad_A` et `bad_G`.

C'est un besoin central de Kairos que l'article ne semble pas structurer au meme niveau.

### 9.2. Traces reactives riches

Kairos veut parler de proprietes sur des traces d'execution reactives:
- entree `i(k)`,
- sortie `o(k)`,
- variables retardees,
- memoire et historique.

L'article semble plus proche d'une verification sur trace de programme annote,
ce qui est plus limite du point de vue semantique.

Cette difference est cruciale si l'on veut verifier des proprietes de surete
portant reellement sur la relation entree/sortie du systeme, et pas seulement
sur l'ordre d'evenements internes observables.

### 9.3. Noyau de preuve mechanise

L'article porte une idee de verification et de generation.
Kairos vise en plus une \emph{preuve mechanisee du schema de reduction lui-meme}.

Donc, meme si l'article est tres proche de Kairos sur l'intuition, il ne remplace
pas le travail Rocq:
- sur la progression,
- sur l'existence d'un pas realise,
- sur la couverture des violations globales par des obligations locales.

### 9.4. Produit comme IR semantique central

L'article semble raisonner en termes de programme annote par un automate.
Kairos fait le pas supplementaire consistant a prendre le produit comme IR
semantique canonique, y compris cote implementation.

C'est un choix plus fort, plus couteux conceptuellement, mais plus stable pour:
- tracer les obligations,
- unifier preuve et implementation,
- et eviter la dispersion de la semantique.

## 10. Outils et travaux connexes

Cette section elargit la comparaison a des outils effectivement proches de
Kairos par certaines dimensions, tout en distinguant soigneusement:
- les outils de preuve ou d'annotation de programme;
- les outils de contrats et de verification de systemes reactifs;
- les outils de monitorage/runtime verification.

Les sources de reference retenues sont:
- Aorai et CaFE sur le site officiel de Frama-C:
  - <https://www.frama-c.com/fc-plugins/aorai.html>
  - <https://www.frama-c.com/fc-plugins/cafe.html>
  - <https://www.frama-c.com/html/kernel-plugin.html>
- AGREE sur le site Loonwerks:
  - <https://loonwerks.com/publications/pdf/backes2021techreport.pdf>
- Kind 2 et CoCoSpec sur le site officiel Kind 2:
  - <https://kind.cs.uiowa.edu/>
  - <https://kind.cs.uiowa.edu/kind2_user_doc/2_input/1_lustre.html>
  - <https://kind.cs.uiowa.edu/papers/CGKT%2B16.pdf>
  - <https://kind.cs.uiowa.edu/papers/LT%2B22.pdf>
- Copilot sur le site du projet:
  - <https://copilot-language.github.io/>

### 10.1. Aorai

Objet:
- verification de proprietes temporelles `LTL` sur programmes `C` via Frama-C.

Technique:
- compilation de la propriete en automate;
- insertion d'annotations ou de contraintes liees a cet automate dans le
  programme;
- decharge vers la chaine Frama-C / Why.

Proximite avec Kairos:
- tres forte sur le schema intellectuel
  `spec temporelle -> automate -> contraintes locales -> backend de preuve`;
- forte aussi sur l'idee de verification de programme, pas seulement de modele;
- c'est l'outil le plus proche de l'article initialement compare.

Difference majeure avec Kairos:
- pas de structure assume/guarantee explicite `A/G` au meme niveau;
- objet semantique apparemment plus proche de la trace de programme annotee que
  de la trace reactive entree/sortie;
- pas de produit `programme x A x G` comme IR semantique central mecanise.

Conclusion locale:
- Aorai est probablement le plus proche de Kairos si l'on regarde uniquement la
  famille ``preuve de programme annote par automate''.

### 10.2. CaFE

Objet:
- verification de proprietes `CaRet` sur programmes `C`.

Technique:
- comme Aorai, CaFE s'insere dans l'ecosysteme Frama-C;
- la difference est que la logique ciblee est orientee appels/retours imbriques,
  donc adaptee aux traces a pile d'appels.

Proximite avec Kairos:
- proche sur l'idee ``propriete temporelle sur programme -> outil de preuve'';
- utile comme point de comparaison lorsque l'on veut distinguer
  `traces de controle/appels-retours` et `traces reactives entree/sortie`.

Difference majeure avec Kairos:
- l'objet semantique est encore plus centre sur la structure d'appel que sur une
  semantique reactive synchrone;
- pas de specification d'entree separee du type `A`;
- pas de noyau de reduction locale prouve a la Rocq.

Conclusion locale:
- CaFE est moins proche de Kairos qu'Aorai, mais il est instructif pour montrer
  que Kairos ne vise pas seulement des proprietes de controle imbrique.

### 10.3. AGREE

Objet:
- preuve de contrats assume/guarantee sur architectures `AADL`.

Technique:
- contrats composes d'hypotheses et garanties;
- verification compositionnelle par k-induction et appels SMT;
- focalisation sur les composants et leurs interfaces.

Proximite avec Kairos:
- tres forte sur la forme logique `assumptions -> guarantees`;
- tres forte sur l'importance d'une specification d'entree/environnement;
- proximite conceptuelle sur la verification de systemes reactifs.

Difference majeure avec Kairos:
- AGREE travaille au niveau architectural/composant, pas au niveau d'un produit
  semantique de programme et d'automates explicites;
- la reduction ``violation globale -> pas local dangereux -> obligation locale''
  n'est pas le coeur expose de la methode;
- ce n'est pas, au sens strict, un outil de preuve de programme annote comme
  Aorai.

Conclusion locale:
- AGREE est plus proche de Kairos sur la logique assume/guarantee que sur la
  mecanique interne de preuve.

### 10.4. Kind 2

Objet:
- verification de systemes reactifs synchrones et de contrats, notamment sur
  programmes Lustre.

Technique:
- model checking / k-induction / IC3 / SMT;
- support de contrats et de la verifiabilite de composants synchrones;
- outillage centre sur les systemes reactifs synchrones.

Proximite avec Kairos:
- proche sur l'objet semantique ``systeme reactif synchrone'';
- proche sur la notion de contrat et de garantie sous hypothese;
- proche sur la manipulation d'un langage synchrone a etats et memoire.

Difference majeure avec Kairos:
- Kind 2 est principalement un verificateur de modeles/programmes synchrones,
  pas un cadre ou la reduction locale est elle-meme isolee et mechanisee en Rocq;
- il n'introduit pas, du moins dans sa presentation standard, un produit
  `programme x A x G` comme IR central documente de la meme facon.

Conclusion locale:
- Kind 2 est un voisin fort de Kairos sur la nature reactive et contractuelle,
  mais moins sur la preuve du schema de compilation lui-meme.

### 10.5. CoCoSpec

Objet:
- langage/specification de contrats pour systemes reactifs synchrones,
  integre a l'ecosysteme Kind 2.

Technique:
- expressions contractuelles haut niveau pour hypotheses, garanties, modes,
  contraintes temporelles structurees;
- compilation vers la chaine de verification des systemes synchrones.

Proximite avec Kairos:
- forte sur le besoin d'exprimer proprement les contrats d'entree et de sortie;
- forte sur l'idee de specification reactive structurante.

Difference majeure avec Kairos:
- CoCoSpec est davantage un front-end/specification language qu'un noyau de
  preuve sur produit d'automates;
- il ne porte pas lui-meme la theorie de correction locale que Kairos cherche a
  stabiliser en Rocq.

Conclusion locale:
- CoCoSpec est plus proche de la couche ``langage de spec'' de Kairos que de son
  noyau Rocq ou de son IR produit.

### 10.6. Copilot

Objet:
- specification de moniteurs temporels embarquables et generation de code de
  monitoring.

Technique:
- langage de flux et de proprietes;
- compilation vers moniteurs executables, souvent en `C`;
- usage centre sur runtime verification embarquee.

Proximite avec Kairos:
- proximite sur la compilation d'une spec temporelle en artefact executable;
- proximite sur la manipulation explicite de memoire/historique et de flux.

Difference majeure avec Kairos:
- Copilot est d'abord un cadre de monitoring, pas une methode de preuve de
  programme ou de reduction vers obligations deductives;
- pas de specification d'entree `A` et de garantie `G` organisees comme dans
  Kairos;
- pas de produit semantique `programme x A x G` prouve.

Conclusion locale:
- Copilot est un voisin interessant pour la compilation de moniteurs, mais reste
  sensiblement plus loin de Kairos que les familles Aorai / AGREE / Kind 2.

### 10.7. Tableau de positionnement

| Outil | Niveau principal | Type de proprietes | Proximite dominante avec Kairos | Ecart principal |
| --- | --- | --- | --- | --- |
| Aorai | Programme C annote | LTL | Automate + annotations + preuve | Pas de `A/G` explicite ni produit `programme x A x G` |
| CaFE | Programme C annote | CaRet | Preuve de programme temporelle | Oriente appels/retours plutot que traces reactives |
| AGREE | Architecture AADL | Assume/guarantee | Hypotheses/garanties explicites | Pas un noyau produit prouve sur programme |
| Kind 2 | Programme/systeme synchrone | Invariants, contrats | Systeme reactif synchrone et contrats | Pas de formalisation Rocq du schema local |
| CoCoSpec | Langage de contrats | Contrats reactifs synchrones | Qualite expressive des contrats | Plus proche du front-end de spec |
| Copilot | Monitoring embarque | Proprietes de flux | Compilation de moniteurs | Runtime verification plutot que preuve deductive |

### 10.8. Bilan comparatif

Si l'on cherche les outils les plus proches de Kairos sur la \emph{preuve de
programme}, alors l'ordre de proximite est probablement:
1. Aorai,
2. CaFE,
3. puis, plus loin, les approches Lustre/PVS ou Kind 2 si l'on accepte
   ``programme synchrone'' au sens large.

Si l'on cherche les outils les plus proches de Kairos sur la \emph{logique
assume/guarantee reactive}, alors l'ordre change:
1. AGREE,
2. Kind 2,
3. CoCoSpec.

Si l'on cherche les outils les plus proches sur la \emph{compilation d'une
propriete temporelle en artefact operationnel}, Copilot redevient pertinent,
mais sur un axe plus runtime que deductif.

La specificite de Kairos reste donc l'intersection de trois dimensions que ces
outils ne couvrent generalement pas ensemble:
- preuve de programme ou de systeme reactif;
- hypothese d'entree explicite `A` et garantie `G`;
- produit semantique central `programme x A x G` relie a une reduction locale
  mechanisee.

## 11. Conclusion strategique

Le verdict est le suivant:

1. Kairos est tres proche de la ligne intellectuelle de l'article.
   Le coeur commun est la reduction d'une propriete temporelle globale a des
   contraintes locales obtenues par synchronisation avec un automate.

2. Kairos va plus loin sur au moins quatre points:
   - specification d'entree explicite via `A`,
   - objet semantique de trace plus riche (entree/sortie/historique),
   - produit explicite `programme x A x G`,
   - noyau interne prouve en Rocq,
   - separation nette entre obligations abstraites et validation externe.

3. L'article reste utile pour Kairos sur deux points:
   - raconter plus algorithmquement la generation des obligations/annotations;
   - garder une presentation plus compacte et plus orientee ``backend concret''.

4. La bonne lecture historique est donc:
   - l'article fournit un precedent fort pour justifier l'architecture
     ``automate + obligations locales + backend externe'';
   - Kairos peut etre vu comme une version plus structuree, plus modulaire et
     plus mechanisee de cette meme idee.

## 12. Consequences concretes pour Kairos

### 11.1. Pour la documentation

Le document
[rocq_oracle_model.tex](/Users/fredericdabrowski/Repos/kairos/spec/rocq_oracle_model.tex)
devrait continuer a renforcer:
- les operateurs explicites d'extraction;
- la projection de chaque famille d'obligations vers le backend;
- la comparaison entre ``etat abstrait du produit'' et ``annotation backend''.

### 11.2. Pour l'implementation

La direction actuelle est confortee:
- garder le produit explicite comme IR semantique central;
- traiter le backend Why3/OBC comme une compilation de cet IR;
- conserver une taxonomie explicite des obligations.

### 11.3. Pour la formalisation Rocq

Un prolongement naturel serait de formaliser encore mieux le pont:
- `GeneratedBy abstrait` -> `famille backend` -> `encodage Why3`.

Cela ferait apparaitre dans Kairos, de facon encore plus nette, ce que l'article
exprime de maniere plus outillee que prouvee: la validite de l'annotation externe
doit bien remonter a la validite de l'obligation abstraite.
