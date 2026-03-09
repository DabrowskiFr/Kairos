# Review critique POPL de `spec/rocq_oracle_model.tex`

Date: 2026-03-07

## Positionnement général

Le document est maintenant beaucoup plus lisible qu'au début du chantier, mais
il reste encore, vu comme soumission POPL, en dessous du niveau attendu sur
quatre axes:

- la hiérarchie des contributions n'est pas encore assez nette;
- certains énoncés mathématiques restent plus forts que ce qui est justifié dans
  le texte;
- la correspondance exacte avec la formalisation Rocq n'est pas toujours rendue
  avec le bon niveau de précision;
- plusieurs sections restent à mi-chemin entre note d'architecture, tutoriel,
  et article de recherche.

## Findings critiques

### 1. Problème de crédibilité sur la sémantique coinductive

La section sur l'``équation coinductive de sémantique'' affichait un résultat
d'existence et d'unicité trop fort au regard de la justification fournie. Pour
un reviewer exigeant, cela affaiblit immédiatement la crédibilité du document:
on ne peut pas invoquer un théorème de copoint fixe sans préciser le cadre
mathématique exact.

Correction à appliquer:
- faire de la définition point par point la définition primaire;
- présenter la lecture coinductive comme une vue équivalente ou un schéma
  standard, et non comme un théorème autonome non prouvé.

### 2. Mélange encore imparfait entre booléens syntaxiques et prédicats sémantiques

Le texte utilisait encore `Bool` pour des objets qui sont, sémantiquement et
dans Rocq, des prédicats (`TickCtx -> Prop`, labels d'arêtes interprétés
logiquement, etc.). Cela crée un flottement inutile entre niveau calculatoire
et niveau logique.

Correction à appliquer:
- utiliser systématiquement `Prop` pour les prédicats sémantiques;
- réserver les booléens aux données de programme quand c'est réellement une
  valeur mémoire.

### 3. Incohérence résiduelle avec Rocq sur `GeneratedBy`

Le papier parlait encore de `GeneratedBy(o,p,phi)` alors que la formalisation
Rocq porte `GeneratedBy o t obl`, avec la transition programme comme témoin
visible et le pas produit comme témoin existentiel interne.

Correction à appliquer:
- aligner la signature mathématique de `GeneratedBy` sur Rocq;
- expliquer que le pas produit reste le témoin interne de la génération.

### 4. Chaîne de preuve encore un peu trop comprimée

Même après amélioration, la chaîne de preuve risquait encore de donner
l'impression d'un saut direct:

global bad -> local bad -> obligation violée -> contradiction.

Pour POPL, il faut rendre plus explicites:
- les hypothèses internes;
- les hypothèses externes;
- le rôle séparé des obligations ``objectif'' et des obligations de support.

Correction à appliquer:
- isoler une sous-section ``Hypothèses du noyau vs hypothèses externes'';
- ajouter un lemme explicite sur les invariants de nœud, pour montrer qu'ils
  participent à la story de preuve sans être confondus avec les obligations
  objectif.

### 5. Le document garde quelques traces de note de conception

Certaines phrases du type ``le présent document'' ou ``cette note'' affaiblissent
le ton de papier de recherche. Ce n'est pas dramatique, mais un reviewer POPL
le lira comme un indice que le texte n'est pas encore complètement stabilisé.

Correction à appliquer:
- préférer des formulations impersonnelles ou centrées sur la contribution;
- réduire les phrases méta-documentaires au strict nécessaire.

### 6. Un bug éditorial visible reste présent

La section sur `StepCtx` contenait une duplication textuelle visible
(`intuition de la structure Rocq sous-jacente` apparaissait deux fois), ce qui
est typiquement le genre d'imperfection qui dégrade la confiance d'un reviewer
sur la rigueur d'ensemble.

Correction à appliquer:
- nettoyage éditorial immédiat.

## Modifications prioritaires demandées

1. Remplacer la pseudo-preuve coinductive par une définition primaire point par
   point, avec la lecture coinductive reléguée en remarque.
2. Passer les prédicats sémantiques à `Prop`.
3. Corriger `GeneratedBy`.
4. Ajouter une clarification structurée des hypothèses de la chaîne de preuve.
5. Ajouter un lemme sur la validité des obligations de support invariants.
6. Nettoyer les incohérences éditoriales restantes.

## Critère de réussite de la prochaine passe

Après correction, un reviewer exigeant doit pouvoir lire le texte comme:

- un papier qui affirme moins, mais mieux;
- un texte où chaque énoncé important a le bon statut mathématique;
- une présentation dont la structure est manifestement calquée sur le noyau
  Rocq, et pas sur une intuition parallèle.
