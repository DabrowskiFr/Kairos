# Objectif et méthodologie de `specv2`

## Objectif

Construire dans `specv2/` une version POPL du travail, indépendante de Kairos
dans son noyau conceptuel, fondée sur :

- une sémantique générale de programmes réactifs ;
- une notion générale de safety conditionnelle ;
- un produit explicite canonique ;
- des clauses sémantiques locales ;
- des triplets de Hoare relationnels ;
- des résultats centraux de correction et de complétude relative.

Le dépôt `specv2/` doit rester autonome :

- papier LaTeX autonome ;
- développement Rocq autonome ;
- structure Dune autonome ;
- documentation locale de méthode et de journal.

## Méthodologie

1. Définir un noyau mathématique minimal mais général.
2. Développer une formalisation Rocq qui suive explicitement les grandes étapes
   conceptuelles du raisonnement.
3. Écrire le papier à partir de cette formalisation, et non l’inverse.
4. Introduire Kairos uniquement comme instance ou raffinement dans une section
   tardive.
5. Compiler régulièrement le Rocq et le papier.
6. Relire chaque passe avec un niveau d’exigence POPL/PLDI.

## Ordre de construction

1. `rocq/ReactiveModel.v`
2. `rocq/ConditionalSafety.v`
3. `rocq/ExplicitProduct.v`
4. `rocq/GeneratedClauses.v`
5. `rocq/RelationalTriples.v`
6. `rocq/Soundness.v`
7. `rocq/RelativeCompleteness.v`
8. `rocq/ResettableDelayExample.v`
9. papier `conditional_safety_local_proofs.tex`

## État courant du noyau

Le noyau Rocq autonome de `specv2/rocq/` compile déjà sous Dune. Les choix
structurants désormais fixés sont :

- un prédicat explicite `WellFormedProgramModel` dans le récit théorique ;
- une cohérence automate définie sémantiquement à partir de l’état produit
  courant, et non par une formule abstraite laissée axiomatique ;
- une relation de matching qui inclut aussi la sortie courante ;
- trois résultats centraux :
  - correction (`validation_conditional_correctness`) ;
  - complétude relative de la partie safety (`relative_completeness_no_bad`) ;
  - complétude relative globale des triples générés
    (`relative_completeness_generated_triples`).

## Discipline scientifique

- peu de résultats centraux ;
- hypothèses explicites ;
- pas de vocabulaire backend dans le noyau ;
- distinction nette entre faits sémantiques, clauses, et triplets ;
- résultas formulés comme théorie de réduction ;
- toute généralité revendiquée doit apparaître dans les définitions et
  théorèmes, pas seulement dans l’introduction.
