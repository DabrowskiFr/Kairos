# Reprise Prompt: `armed_delay` et clauses de phase source

Ce document sert de point de reprise pour un chantier futur sur la projection
des obligations locales quand une garantie LTL encode une activation
historique, par exemple :

- `G (arm = 1 => X G (y = prev x))`

Le cas directeur est :

- `/Users/fdabrowski/Repos/kairos/kairos-dev/tests/others/armed_delay.kairos`

## Constat

Sur `armed_delay`, le model checking "comprend" naturellement la propriété,
car l'information historique "on a déjà armé" est portée par les états de
l'automate de garantie et donc par les états du produit.

En revanche, la projection actuelle vers les obligations locales exportées ne
préserve pas assez précisément cette information de phase. On obtient alors des
VCs locales trop fortes, par exemple sur des pas issus de `Idle`, où l'on
demande encore de prouver `y = prev x` alors que le code exécute :

```kairos
y := 0;
z := x;
```

Le symptôme typique observé est l'apparition de goals du style :

- `step_tr_*_ps_*_g1_*`

avec :

- un pré trop faible,
- une postcondition `y = prev x`,
- appliquée à un pas local pour lequel cette obligation ne devrait être active
  qu'en présence d'une activation historique préalable.

## Ce qu'il ne faut pas faire

Pour ce chantier, les solutions suivantes sont explicitement écartées :

- ajouter ou réintroduire un moniteur/automate caché dans le code Why généré ;
- ajouter des affectations ghost de type `__pre_k*` ou `__aut_state` ;
- "sauver" la preuve par instrumentation locale du backend Why ;
- corriger le problème par un simple filtrage syntaxique des gardes du produit ;
- bricoler l'exemple pour faire croire que le backend est réparé.

Les expérimentations suivantes ont déjà été tentées et n'ont pas suffi :

- ajout d'une locale `armed_seen` dans l'exemple ;
- ajout d'invariants d'état autour de `armed_seen` ;
- exposition de `armed_seen` comme sortie et reformulation de la spec dessus.

Ces variantes déplacent les goals rouges, mais ne corrigent pas le problème de
fond dans la chaîne d'export.

## Hypothèse de travail

Le problème vient du fait que la projection actuelle exporte encore des
obligations locales "plates" à partir des phases de garantie, alors qu'il
faudrait exporter des **clauses caractérisant ce que signifie être dans un état
source du produit**.

Dit autrement :

- le produit explicite sait porter l'histoire via ses états ;
- la projection locale ne doit pas aplatir trop tôt cette histoire en une
  simple postcondition instantanée ;
- elle doit exporter une clause de source suffisamment forte, puis prouver la
  transformation de cette clause vers une clause de destination.

## Idée concrète

Pour un état source du produit `(P,A,G)`, exporter une formule de synthèse
`R(P,A,G)` qui sert d'interface logique locale.

Les obligations locales devraient alors avoir la forme :

1. hypothèse de source :
   - `R(P,A,G_src)`
2. exécution du pas programme
3. objectif :
   - établir `R(P',A',G_dst)` pour la destination suivie
   - ou établir une clause d'exclusion si le cas est `BadGuarantee`

Sur `armed_delay`, l'intuition à vérifier est la suivante :

- `R(Idle, A0, G0) := true`
- `R(Track, A0, G1) := z = prev x`
- `R(Idle, A0, G1) := false`

Le point important est que certains couples `(état programme, état de phase)`
ne doivent pas devenir directement des contextes locaux ordinaires ; ils doivent
être traités comme des états source incohérents ou inatteignables.

## Question de recherche précise

Comment exporter, dans l'IR puis dans les clauses noyau, des **clauses de
cohérence d'état source** et des **clauses de transition entre résumés
source/destination**, au lieu de projeter directement une formule LTL brute
comme postcondition locale ?

## Pistes à examiner

1. Identifier où la chaîne perd aujourd'hui l'information "pourquoi on est dans
   cette phase".
   - regarder la projection depuis `product_contract` / `product_case`
   - regarder les clauses noyau associées aux états source du produit

2. Distinguer explicitement deux familles de clauses :
   - clauses de cohérence d'état source ;
   - clauses de préservation/transition locale.

3. Vérifier si certaines obligations sortantes ne devraient être générées que
   depuis les états source cohérents, et non depuis tous les couples
   `(P,A,G)` présents dans la sur-approximation structurelle.

4. Rejouer `armed_delay` comme cas directeur.

## Prompt de reprise

Utiliser le prompt suivant pour reprendre le chantier :

> Reprendre l'analyse de `armed_delay` sans instrumentation du backend Why et
> sans ajout de moniteur caché. Le but est de restructurer la projection des
> obligations locales pour les garanties activées par l'histoire. Partir du
> produit et des clauses exportées, puis concevoir une exportation où chaque
> état source du produit porte une clause de cohérence `R(P,A,G)` et où les pas
> locaux prouvent des transitions entre résumés source/destination, au lieu de
> prouver directement une postcondition LTL aplatie. Utiliser `armed_delay`
> comme cas directeur et expliquer concrètement comment éviter les VCs absurdes
> depuis `Idle` avec phase `G1`.
