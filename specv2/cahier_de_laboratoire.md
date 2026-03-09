# Cahier de laboratoire `specv2`

## 2026-03-08

- Ajout d'une instanciation Rocq concrète de `resettable_delay` dans `rocq/ResettableDelayExample.v`.
- Choix de modélisation pour cette instance :
  - programme réactif concret avec états `RDInit` / `RDRun` et quatre transitions explicites `TInitReset`, `TInitData`, `TRunReset`, `TRunData` ;
  - automate d'hypothèse concret pour la discipline `reset -> x = 0` ;
  - automate de garantie concret avec état infini `GAfterData z`, ce qui permet de mémoriser la dernière valeur pertinente de `x` dans l'automate lui-même ;
  - invariant local concret reliant la mémoire du programme à l'état courant de l'automate de garantie (`cur_mem = 0` en `GAfterReset`, `cur_mem = z` en `GAfterData z`).
- Résultats concrets obtenus dans `ResettableDelayExample.v` :
  - `resettable_delay_correct`.
- Compilation Rocq complète revalidée via `opam exec --switch=5.4.1+options -- dune build`.
- Conclusion scientifique :
  - `specv2` n'est pas "trop abstrait" pour récupérer une preuve concrète ;
  - il faut en revanche ajouter explicitement une couche d'instanciation sémantique ;
  - l'automate de garantie de cette instance peut être infini, ce qui est compatible avec le noyau abstrait et permet de traiter le cas `prev x` sans réintroduire une syntaxe Kairos dans la formalisation.
- Passe de nettoyage ensuite appliquée à `ResettableDelayExample.v` :
  - suppression de la couche devenue inutile pour les invariants et triples générés ;
  - conservation du seul résultat final utile ici : `resettable_delay_correct`.
- Réorientation méthodologique ensuite demandée :
  - abandon de la preuve directe de `resettable_delay_correct` ;
  - réintroduction d'un invariant concret, d'un lemme de vérité de cet invariant sur les runs, et d'un théorème `resettable_delay_generated_triples_valid` ;
  - reformulation finale de `resettable_delay_correct` comme application explicite du théorème abstrait `validation_conditional_correctness`.

- Nouvelle passe de review senior de niveau POPL/PLDI/LICS/FMCAD sur `conditional_safety_local_proofs.tex`.
- Production de `review_iteration_06.md`.
- Finding bloquant identifié pendant la review :
  - le papier affirmait encore la complétude relative des triples générés au sens d'une validité sur toutes les exécutions, alors que la formalisation Rocq prouve cette partie seulement sur les exécutions admissibles (`TripleValidOnAdmissibleRuns`);
  - même dérive pour la notion exposée d'invariants vrais, trop forte dans le papier par rapport à Rocq.
- Corrections appliquées au papier :
  - introduction resserrée pour réduire les redites sur la thèse centrale ;
  - ajout de la notion explicite `\ValidAdm` pour la validité des triples sur exécutions admissibles ;
  - réalignement des deux théorèmes de complétude relative et de leurs preuves sur cette notion admissible ;
  - réalignement de `InvTrue` sur la version Rocq : invariants vrais sur exécutions admissibles ;
  - clarification du statut de `\Ctx` dans la définition de clause sémantique ;
  - correction de l'explication du lemme d'activation des triples `NoBad`.
- Recompilation LaTeX complète via `latexmk -pdf -interaction=nonstopmode conditional_safety_local_proofs.tex` : OK.
- Résultat de compilation :
  - PDF régénéré dans `conditional_safety_local_proofs.pdf` ;
  - plus de warning structurel bloquant ;
  - un très léger overfull résiduel subsiste (`1.37907pt`) dans la méta-théorie ;
  - PDF final à 26 pages, ce qui impose désormais une discipline stricte sur le budget de 25 pages de texte hors bibliographie.
- Production d'une mini-review post-correction dans `review_iteration_07.md`.

- Iteration de review stricte de niveau POPL/PLDI sur `conditional_safety_local_proofs.tex`.
- Production de `review_iteration_01.md` avec findings classés par sévérité.
- Corrections appliquées au papier :
  - abstract recentré sur les trois résultats principaux ;
  - introduction renforcée sur le statut "reduction theorem" ;
  - labels explicites ajoutés aux principaux résultats ;
  - clarification du sens de la relative completeness par rapport à Cook/Hoare ;
  - explicitation du fait que les cinq familles de triples forment exactement l’ensemble généré ;
  - related work mieux relié aux observers synchrones.
- Recompilation LaTeX réussie et sans warning final.
- Production d’une seconde mini-review dans `review_iteration_02.md`.
- Deuxième itération de review axée sur la nouveauté perçue et le caractère
  principiel de la réduction.
- Production de `review_iteration_03.md`.
- Corrections apportées au papier :
  - explicitation du point non trivial : identifier l’objet sémantique qui rend
    les preuves locales inévitables et backend-indépendantes ;
  - renforcement du paragraphe de contributions sur le statut du produit et des
    triples ;
  - renforcement du sens de la relative completeness comme adéquation de la
    couche de réduction ;
  - amélioration du related work pour mieux distinguer la contribution
    sémantique d’une simple présentation système ;
  - conclusion recentrée sur le théorème de réduction.

- Initialisation du chantier `specv2/` comme espace autonome dédié à une
  version POPL du travail.
- Création d’un projet Dune/Rocq local dans `specv2/`.
- Création d’un fichier `objectif_methodologie.md` pour fixer le cap
  scientifique.
- Décision de construire une formalisation indépendante de Kairos, puis de
  réécrire le papier à partir de cette formalisation.
- Développement d’un nouveau noyau Rocq autonome dans `specv2/rocq/` :
  modèle réactif, safety conditionnelle, produit explicite, clauses,
  triplets relationnels, correction, complétude relative.
- Plusieurs erreurs de généralisation de sections ont été corrigées en rendant
  explicites certains paramètres inférés par Rocq.
- Un trou conceptuel a été détecté puis corrigé : la relation de matching doit
  inclure la sortie courante, sinon la cible d’un pas produit n’est pas
  déterminée correctement.
- Un second point conceptuel a été corrigé : la propagation des invariants
  utilisateur doit partager le contexte de cohérence automate, sinon la cible
  concrète du pas n’est pas suffisamment contrainte pour la preuve de
  complétude relative.
- Le développement `specv2/rocq/` compile maintenant sous
  `opam exec --switch=5.4.1+options -- dune build`.
- Rédaction d’un nouveau papier autonome
  `conditional_safety_local_proofs.tex` centré sur une réduction sémantique
  générale de la safety conditionnelle vers des preuves locales.
- Première passe de relecture de niveau POPL/PLDI : recentrage des claims sur
  trois résultats (soundness, complétude relative de la safety, complétude
  relative des triples générés), clarification de la frontière entre cœur
  mathématique et instanciations backend, et réécriture du related work par
  principes plutôt que par simple liste d’outils.
- Seconde passe de relecture stricte : remplacement de `non-bounded` par
  `unbounded`, réduction des énumérations inutiles, resserrement de
  l’introduction et de la conclusion, et nettoyage du dernier warning LaTeX.
- Compilation complète du papier via
  `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode conditional_safety_local_proofs.tex`
  avec succès et sans warning résiduel.
- Réalignement des théorèmes exposés avec l’intention auditée : les énoncés
  publics ne mentionnent plus explicitement une mémoire initiale `m0`, qui
  reste cantonnée aux lemmes internes paramétrés. Ajout dans Rocq d’une couche
  exposée sans `m0` pour la correction et la complétude relative.
- Élargissement substantiel du papier `conditional_safety_local_proofs.tex` :
  développement de l’introduction, ajout de motivations conceptuelles sur la
  couche intermédiaire sémantique, enrichissement du running example,
  dépliage des sections `Semantic Model`, `Reduction to Local Proofs`,
  `Meta-Theory`, `Instantiation`, `Related Work` et `Conclusion`.
- Stabilisation d’une version plus proche d’un vrai papier de conférence :
  10 pages de contenu compilé, sans warnings LaTeX, avec une séparation plus
  nette entre théorie centrale et raffinements backend.
- Ajout explicite, dans la section de méta-théorie du papier, de trois lemmes
  intermédiaires qui rendent le raisonnement plus lisible : matching du pas
  sélectionné, tenue des faits de cohérence sur les exécutions admissibles, et
  activation locale d’un triple de sécurité par un pas dangereux réalisé.
- Renforcement supplémentaire du papier pour sortir d’une version trop
  condensée : enrichissement du running example avec un cas dangereux concret,
  ajout d’explications plus substantielles dans le modèle sémantique, la
  réduction et la méta-théorie, et création d’une annexe qui explicite la
  structure des preuves ainsi que la correspondance avec le développement Rocq.
- Restauration explicite du fil rouge dans le papier POPL : le running example
  est maintenant annoncé comme réutilisé jusqu’à la section d’instanciation,
  et la section `Instantiation and backend refinements` contient de nouveau une
  sous-section présentant une instance Kairos concrète du même exemple, avec un
  nœud complet en syntaxe source et une explication du passage vers les triples
  locaux. Recompilation LaTeX complète réussie (`conditional_safety_local_proofs.pdf`,
  12 pages) sans warning résiduel.
- Simplification du noyau abstrait : suppression complete de `InitMem` / `init_mem_ok` dans `ReactiveModel.v`, `RelationalTriples.v`, `Soundness.v` et `RelativeCompleteness.v`. Le modele abstrait autorise maintenant toute memoire initiale ; les theoremes exposes et le papier parlent simplement d'executions, plus d'executions admissibles au sens d'une contrainte initiale cachee. Recompilation Rocq via `dune build` et LaTeX via `latexmk` reussies.
- Remplacement, dans la section d'instanciation de `conditional_safety_local_proofs.tex`, du pseudo-code Kairos par le vrai exemple `resettable_delay.kairos` du dépôt. Le fil rouge abstrait et la section Kairos concrète reposent maintenant sur le même programme, ce qui rétablit la continuité pédagogique voulue.
- Renforcement de l'isomorphie narrative entre le fil rouge formel et l'exemple Kairos concret : l'overview de `conditional_safety_local_proofs.tex` reprend maintenant explicitement la vraie hypothese d'entree, les trois garanties et l'invariant utilisateur a deux cas de `resettable_delay.kairos`, au lieu d'une version lissee. Le lecteur voit donc bien le meme exemple sous vue abstraite puis sous vue Kairos.

## 2026-03-08
- Rewrote the `Semantic Model` and `Reduction to Local Proofs` sections of `conditional_safety_local_proofs.tex` from semi-formal narrative into explicit mathematical definitions (reactive programs, executions, safety automata, product states and steps, tick contexts, matching, dangerous steps, semantic clauses, relational triples, and canonical generated triples).
- Realigned the paper with the abstract Rocq development by making the main meta-theoretic theorems rest on named definitions rather than descriptive prose.
- Fixed notation gaps introduced by the rewrite and compacted the local-context definitions to remove layout overflow.

- Reintroduced the running example systematically inside the formal core of the paper: after the definitions of reactive programs, conditional safety, explicit product, dangerous steps, and generated triples, each with a short instantiation on resettable-delay.

- Reworked the related-work section by restoring a broader and more principled bibliography: classical temporal logic and safety, synchronous observer-based verification, deductive compilation of temporal properties (Aorai/CaFE), contract-based reactive verification (AGREE/Kind 2), and runtime monitoring (Copilot).
- Performed a targeted rewrite of the central narrative of `conditional_safety_local_proofs.tex`: the abstract, introduction, overview, and opening of the metatheory now present the work primarily as a semantic reduction theorem rather than as a clean verification pipeline.
- Removed premature mentions of Kairos from the front of the paper so that the tool only reappears in the instantiation section, in line with the intended structure of the paper.
- Strengthened the overview so that the dangerous step, semantic safety clause, and local relational triple appear as the canonical local objects of the reduction before the formal definitions begin.
- Strict formalization pass on the core sections of `conditional_safety_local_proofs.tex`: replaced remaining textual placeholders by explicit definitions for `WF(P)`, `\AvoidA`, `\AvoidG`, `\AvoidGAdm`, context projections, `\TransRel_t`, `\Valid`, product-state projections, `\Bad`, `\mathsf{WFStep}`, and the global predicates `\GlobCorr` and `\InvTrue`.
- The generated-triples layer is now stated as explicit mathematical objects (`h^{init}_{Inv}`, `h^{init}_{Coh}`, propagation families, and `h^{NoBad}`) plus a formal predicate `\Generated(h)` rather than as a descriptive list only.

## 2026-03-08
- Passe de normalisation formelle dans le coeur de `conditional_safety_local_proofs.tex` : ajout de la définition du pas produit sélectionné, réécriture des lemmes centraux de la méta-théorie sous forme complètement quantifiée, suppression du dernier reste d'intuition à l'intérieur de la définition de `Product step`.

## 2026-03-08
- Alignement du papier `specv2` sur le noyau Rocq pour la notion de programme : la totalité du tick et l'activation de la transition sélectionnée sont désormais intégrées à la définition de programme, `WF(P)` a été retiré comme hypothèse séparée des théorèmes exposés.

## 2026-03-08
- Alignement de la présentation des automates dans le papier sur `specv2/rocq` : totalisation du pas automate rendue explicite dans la définition, et contrainte `q_0 
eq q_{bad}` intégrée à la présentation de la spécification conditionnelle.

## 2026-03-08 — Alignement papier/Rocq sur la notion de pas produit

- Relecture ciblée du coeur formel du papier après signalement d'une incohérence non détectée.
- Incohérence identifiée : dans le papier, `WFStep(p)` décrivait un pas réalisé sur un run, alors que dans `specv2/rocq`, `product_step_wf` est une propriété structurelle du pas produit.
- Correction appliquée dans `conditional_safety_local_proofs.tex` :
  - introduction explicite du constructeur de cible `Target(src,t,m,i,o)` ;
  - redéfinition de `WFStep(p)` comme égalité structurelle `p_dst = Target(...)` ;
  - conservation de `Match` comme notion sémantique de réalisation concrète ;
  - ajout du lemme intermédiaire `Realized steps are well formed` pour relier les deux niveaux ;
  - réalignement des triples canoniques avec Rocq : préconditions de propagation et de sécurité incluent désormais `Match`, la cohérence courante, et l'invariant utilisateur ; le triple `NoBad` conclut vers `\bot` et non plus directement vers la clause `NoBad(p)`.
- Cette passe corrige un vrai écart conceptuel entre papier et Rocq ; les définitions du coeur formel sont maintenant plus fidèles à `GeneratedClauses.v` et `RelationalTriples.v`.

## 2026-03-08 — Preuves détaillées rapatriées dans le corps du papier

- Réécriture de la section de méta-théorie pour développer les preuves dans le corps plutôt que dans une annexe séparée.
- Les preuves de soundness et de relative completeness sont maintenant détaillées dans le texte principal ; l'annexe ne garde plus qu'une table de correspondance avec les fichiers Rocq.
- Motivation : éviter l'effet "preuve réelle en annexe" et faire porter le coeur de l'argument mathématique par le papier lui-même.
- Au passage : correction d'une incohérence supplémentaire entre papier et Rocq sur la forme exacte des triples générés (`NoBad` conclut vers `\bot`, les préconditions des triples de propagation et de sécurité incluent `Match` et la cohérence courante).

## 2026-03-08 — Réinjection sélective des éléments pédagogiques utiles du premier papier

- Réintégration, dans `conditional_safety_local_proofs.tex`, des éléments du premier papier qui renforcent réellement la version théorique :
  - figure compacte du fragment de produit pertinent avec pas dangereux mis en évidence ;
  - explicitation nette des cinq familles de triples générés ;
  - densification de la section d'instanciation autour du vrai exemple Kairos `resettable_delay` ;
  - mise en avant plus explicite de la chaîne `violation globale -> pas dangereux -> clause NoBad -> triple local`.
- Choix méthodologique : ne réinjecter que ce qui renforce la lisibilité théorique et le fil rouge, sans réintroduire la lourdeur outil-centrée du premier papier.
- Vérification de compilation après ajout de la figure et des nouveaux passages ; derniers défauts de mise en page éliminés.

## 2026-03-08 — Migration du papier `specv2` vers le gabarit ACM/PACMPL

- Reprise de la mise en forme LaTeX pour utiliser le style ACM/PACMPL habituel, avec `acmart` comme classe principale.
- Première tentative avec citations author-year forcées : échec, car le style bibliographique ACM généré n'était pas compatible avec cette configuration.
- Correction retenue :
  - conservation de `acmart` ;
  - suppression du forçage author-year ;
  - passage en mode `nonacm` pour obtenir un brouillon propre au style ACM sans exiger les métadonnées éditoriales ACM (CCS, acmref, copyright).
- Ajout de `\\raggedbottom` pour éliminer les warnings de pagination (`Underfull \\vbox`) restants.
- Résultat :
  - `conditional_safety_local_proofs.tex` compile proprement ;
  - le PDF final suit maintenant le gabarit ACM/PACMPL usuel ;
  - plus de warnings LaTeX bloquants ni de warnings résiduels de format.
## 2026-03-08\n- Added LaTeX listings-based syntax highlighting for the concrete Kairos example in the POPL paper, with a lightweight custom language definition and framed rendering.\n- Recompiled conditional_safety_local_proofs.pdf successfully after the change.
## 2026-03-08\n- Verified visually that the abstract was present in the ACM front matter but visually ambiguous because it had no heading.\n- Added an explicit 'Abstract.' lead-in inside the abstract environment and recompiled.
## 2026-03-08\n- Added a pedagogical pass to the POPL paper: intuition paragraphs before the central formal blocks in the semantic model and reduction, plus a reading guide at the start of the metatheory.\n- Recompiled the paper successfully after the rewrite.
## 2026-03-08\n- Added a short Background section after the introduction to explain the synchronous reactive setting, safety over infinite traces, assume/guarantee automata, and local relational proof obligations before the overview and formal model.\n- Recompiled the paper successfully after the reorganization.

- Ajout dans la section d'instanciation d'un extrait OBC+ decore pour `resettable_delay`, avec explication ligne par ligne des contraintes `Compatibility`, `AssumeAutomaton`, `Coherency` et `Instrumentation` comme images concretes des familles abstraites de triples.

## 2026-03-08 — Passe bibliographique et DOI

- Audit des references effectivement citees dans `conditional_safety_local_proofs.tex`.
- Verification de l'existence des articles/livres/outils cites et normalisation des types BibTeX correspondants.
- Reecriture de `references.bib` pour homogeniser :
  - types (`@article`, `@inproceedings`, `@book`, `@techreport`, `@misc`) ;
  - metadonnees de base (venue, serie, volume, pages, publisher) ;
  - DOI quand ils existent ;
  - URL explicites quand il s'agit de documentation ou d'artefacts sans DOI stable.
- Ajout des champs `address` attendus par le style ACM pour eliminer les warnings BibTeX residuels.
- Resultat : compilation LaTeX propre, plus de warnings BibTeX, bibliographie plus uniforme et plus credible scientifiquement.

## 2026-03-08 — Background: model checking non borne et automates de surete

- Renforcement de la section `Background` pour mieux justifier l'interet de l'approche deductive sur programmes reactifs a domaines non bornes.
- Ajout d'un paragraphe expliquant que le model checking fini n'est pas directement applicable aux etats programmes contenant entiers, structures ou memoires non bornees, et qu'il faut alors soit abstraire, soit se restreindre, soit utiliser des techniques d'etats infinis.
- Ajout de references de cadrage :
  - `bouajjani-pushdown`
  - `clarke-cegar`
- Renforcement du passage sur les automates de surete :
  - rappel que la representation deterministe n'est pas un choix d'implementation ad hoc, mais la forme adaptee a la localisaton des prefixes mauvais ;
  - references maintenues vers `kupferman-vardi-safety` et `gastin-oddoux`.

## 2026-03-08 — Related work: lignée Lustre/PVS (Caspi, Dumas)

- Ajout dans `references.bib` de trois references supplémentaires pour situer plus précisément la lignée de vérification déductive synchrone autour de Lustre et PVS :
  - la thèse de Cécile Dumas Canovas sur la preuve déductive de programmes Lustre ;
  - `A Methodology for Proving Control Systems with Lustre and PVS` ;
  - `A PVS Proof Obligation Generator for Lustre Programs`.
- Intégration de ces références dans la section `Related Work` pour mieux ancrer l’article dans la tradition de la preuve déductive de programmes synchrones, au-delà des seules références d’outils plus récentes.
- Recompilation du papier après mise à jour bibliographique : OK.

## 2026-03-08 — Zotero references on deductive verification vs model checking
- Added Gesell 6 Schneider on Hoare reasoning for synchronous languages and state-space explosion.
- Added STeP as a reactive-systems precursor combining deductive and algorithmic verification on infinite data domains.
- Integrated both in the Background/Related Work of specv2.

## 2026-03-08 — Normalisation finale des références Lustre/PVS
- Complété l’entrée `lustre-pvs-methodology` avec volume, éditeurs, pages et publisher vérifiés depuis la bibliographie PVS.
- Recompilé le papier après mise à jour de `references.bib`.
- Résultat : PDF généré proprement, sans nouveau warning BibTeX bloquant.

## 2026-03-08 — Séparation Background / Related Work
- Allégé `Background` pour en faire un cadre technique minimal (ticks synchrones, safety, automates, preuve locale).
- Déplacé les citations et contrastes comparatifs (Fix–Grumberg, Yahav et al., Gesell–Schneider, STeP) vers `Related Work`.
- Recompilé : PDF propre, 23 pages, pas de warning bloquant.

## 2026-03-08 pedagogie (6 points)
- Renforcement du fil rouge avec un encadre synthetique "Reduction at a glance" dans l'overview.
- Reintroduction explicite du fil rouge au niveau des triples relationnels.
- Ajout d'un paragraphe de lecture fonctionnelle des cinq familles de triples apres leur enumeration.
- Ajout de paragraphes "Proof idea" pour les trois theoremes centraux.
- Renforcement de la separation entre coeur theorique et instanciation au debut de la section d'instanciation.
- Recompilation complete du papier apres cette passe pedagogique.

## 2026-03-08 — Unification de `AvoidG`
- Suppression du double niveau expose `AvoidG(m_0,u)` / `AvoidGAdm(u)` dans `specv2`.
- Nouveau choix theorique :
  - une seule notion exposee `AvoidG(u)`, qui quantifie directement sur toutes les memoires initiales ;
  - les preuves internes gardent `m_0` comme variable locale, mais pas comme seconde notion semantique.
- Mise a jour Rocq :
  - `ConditionalSafety.v` : `AvoidG` devient la notion unique exposee ;
  - `Soundness.v` et `RelativeCompleteness.v` : `globally_correct` est reformule directement avec `AvoidG u` ;
  - suppression des corollaires/definitions exposees devenus redondants.
- Mise a jour papier :
  - suppression de `\\AvoidGAdm` ;
  - definition unique de `\\AvoidG(u)` ;
  - reformulation de la proposition de localisation pour eviter une notation auxiliaire sur l'execution fixe.
- Point technique :
  - `trace_from` n'a pas exactement le meme regime d'arguments dans `ConditionalSafety.v` (section locale) et dans les fichiers qui l'importent ;
  - la correction retenue est `trace_from m0 u` dans `ConditionalSafety.v` et `trace_from P m0 u` dans les fichiers clients.
- Validation :
  - `opam exec --switch=5.4.1+options -- dune build` OK
  - `opam exec --switch=5.4.1+options -- latexmk -g -pdf -interaction=nonstopmode conditional_safety_local_proofs.tex` OK

## 2026-03-08 — Passe de cohérence des noms Rocq
- Harmonisation des noms dans `specv2/rocq/` pour rendre la structure plus lisible.
- Convention retenue :
  - suffixe `_from` pour les objets dépendant d'une exécution fixée ;
  - noms compacts pour les lemmes structurels ;
  - vocabulaire homogène autour de `coherence`.
- Renommages principaux :
  - `cfg_at_from`, `state_at_from`, `mem_at_from`, `trans_at_from`, `out_at_from`
    deviennent `cfg_from`, `state_from`, `mem_from`, `trans_from`, `out_from` ;
  - `product_state_at_from`, `ctx_at_from`, `product_select_at`
    deviennent `product_state_from`, `ctx_from`, `selected_step_at` ;
  - `coherence_current` devient `coherence_now` ;
  - `init_automaton_triple` / `automaton_triple`
    deviennent `init_coherence_triple` / `coherence_triple` ;
  - `current_context_matches_selected_step`
    devient `selected_step_matches_ctx` ;
  - `global_violation_yields_dangerous_step`
    devient `dangerous_step_of_global_violation` ;
  - `node_invariants_true_on_admissible_runs`
    devient `node_invariants_on_runs`.
- Validation :
  - `opam exec --switch=5.4.1+options -- dune build` OK
  - recompilation LaTeX du papier OK

## 2026-03-08 — Review iteration 05 (alignment with mechanized soundness)
- Produced `review_iteration_05.md` as a mini-review after correcting the soundness mismatch.
- Verified that the paper now states soundness with both generated-triple validity and semantic truth of user invariants, in line with `specv2/rocq/Soundness.v`.
- Verified that `GlobCorr` and `InvTrue` are defined before use in the Meta-Theory section.
- Recompiled the paper successfully with `latexmk`; no new LaTeX issue introduced by this correction.


- 2026-03-08: extraction des notations et macros de couleur dans definitions.tex pour centraliser les commandes du papier et fiabiliser les notations.
## 2026-03-08 — Clarification of transition guards in the paper
- Aligned the paper with the Rocq treatment of program guards.
- Made explicit that guards are represented by `enabled`, enforced by `select`, and therefore exploited through realized steps (`Match`) and relational transition semantics (`TransRel_t`) rather than repeated as ad hoc conjuncts in local preconditions.
- Recompiled `conditional_safety_local_proofs.tex` successfully after the clarification.

## 2026-03-08 — Added Why3 solving time for the running example
- Measured the concrete Why3/Z3 discharge time of the running example using the documented transformations (`simplify_formula`, `eliminate_if_term`, `remove_unused`, `split_vc`) and a 30s timeout per goal.
- Recorded in the paper that the generated Why3 file is discharged in about 4.4s of wall-clock time on the local Apple M2 development machine.
- Framed this measurement explicitly as a reproducibility indicator for the example, not as a performance claim.

## 2026-03-08 — Expanded machine and tool configuration for the timing note
- Enriched the Why3 timing note in the paper with the concrete local configuration used for the measurement.
- Added the versions of Why3 (`1.8.2`) and Z3 (`4.15.2`).
- Added the local machine characteristics relevant for reproducibility: Apple M2, 8 cores, 16 GB RAM, macOS 15.6 / Darwin 24.6.0.
- Cleaned the surrounding prose so that the timing note reads as a reproducibility note rather than an experimental-performance claim.

## 2026-03-08 — Mechanization section: concrete example and line counts
- Updated the `Mechanization` section of the paper to mention the new Rocq file `ResettableDelayExample.v`.
- Made explicit that this file instantiates the abstract development on the running `resettable_delay` example and concludes `resettable_delay_correct` by proving the generated triples valid and applying the abstract soundness theorem, rather than by a direct semantic proof.
- Replaced the previous coarse file inventory with a table giving, for each Rocq file, the number of specification lines, proof lines, and total lines.
- Refined the presentation choice afterwards: the table now gives only per-file specification and proof counts; the combined spec+proof total is stated only globally, not for each file.
- Removed `rocq/Main.v`, which only reexported the development and was not used by the proofs or by the build.
- Updated the mechanization counts accordingly:
  - specification: 730
  - proof: 487
  - total spec+proof: 1217
- Recorded the counting convention in the paper: non-empty, non-comment lines outside proof blocks count as specification; lines from `Proof.` to `Qed.` or `Defined.` count as proof.
- Updated the global counts in the paper to:
  - specification: 730
  - proof: 487
  - total spec+proof: 1217
- Recompiled `conditional_safety_local_proofs.tex` successfully after the edit.
- Outcome:
  - the PDF still compiles cleanly;
  - the document remains at 26 pages;
  - the only residual layout issue is the previously existing tiny overfull box.

## 2026-03-08 — Compactage des figures d'automates et de triples
- Reduced the scale of the three main schematic figures in the paper to improve page density without changing their content.
- `Safety automata for the running example`:
  - reduced the global resize factor;
  - tightened horizontal spacing between states;
  - slightly reduced node sizes.
- `Relevant fragment of the explicit product`:
  - reduced the global resize factor from full width;
  - tightened the spacing between source and target states;
  - reduced box widths and heights.
- `Initialization and propagation triples`:
  - reduced the global resize factor;
  - tightened horizontal and vertical spacing between nodes;
  - slightly reduced box sizes.
- Recompiled `conditional_safety_local_proofs.tex` after the compacting pass.
- Outcome:
  - the PDF still compiles cleanly;
  - the document remains at 26 pages;
  - the only residual warning is the previously existing tiny overfull box unrelated to these figures.

## 2026-03-08 — Future work added to the conclusion
- Expanded the conclusion with a dedicated `Future work` paragraph instead of leaving the outlook as a single closing sentence.
- Structured the opening around three concrete directions:
  - richer safety-specification fragments that still compile cleanly to automata and generated triples;
  - tighter links between the abstract semantic clauses and proof-producing verification backends;
  - more systematic embeddings for synchronous source languages with richer state structures.
- Kept the framing aligned with the paper's current thesis: future work should refine the instantiation layers rather than complicate the abstract core.

## 2026-03-08 — Rocq documentation hierarchy and in-file explanations
- Added a documentation package declaration in `dune-project` and a `documentation` stanza in `rocq/dune`.
- Added thematic `.mld` pages in `rocq/`:
  - `index.mld`
  - `model.mld`
  - `reduction.mld`
  - `metatheory.mld`
  - `example.mld`
- Chosen structure:
  - one top-level landing page;
  - four thematic pages matching the scientific decomposition of the development;
  - explicit links from pages to the corresponding Rocq modules.
- Added substantial documentation comments `(** ... *)` directly in the Rocq files to explain:
  - the role of each module;
  - the main semantic notions and records;
  - the interpretation of the central definitions;
  - the purpose of the key lemmas and theorems.
- Files enriched with documentation comments:
  - `ReactiveModel.v`
  - `ConditionalSafety.v`
  - `ExplicitProduct.v`
  - `GeneratedClauses.v`
  - `RelationalTriples.v`
  - `Soundness.v`
  - `RelativeCompleteness.v`
  - `ResettableDelayExample.v`
- Attempt that failed:
  - first `dune build` from `rocq/` reused the repository-wide Dune build directory under `/Users/fredericdabrowski/Repos/kairos/_build` and hit a corrupted stale lock file (`_build/.lock` not containing a valid PID);
  - rather than touching the parent repository outside `specv2/`, the build was rerun with local build directories inside `specv2/rocq`.
- Validation:
  - `DUNE_BUILD_DIR=/Users/fredericdabrowski/Repos/kairos/specv2/rocq/_build_local opam exec --switch=5.4.1+options -- dune build` succeeded;
  - `DUNE_BUILD_DIR=/Users/fredericdabrowski/Repos/kairos/specv2/rocq/_build_local_doc opam exec --switch=5.4.1+options -- dune build @doc` succeeded;
  - generated documentation entry point observed at:
    `/Users/fredericdabrowski/Repos/kairos/specv2/rocq/_build_local_doc/default/specv2/rocq/SpecV2.html/index.html`.

## 2026-03-08 — Front matter preprint label
- Overrode the `acmart` journal bibstrip in the preamble so that the footer now displays `Preprint` instead of the PACMPL journal string.
- Kept the rest of the ACM-style layout unchanged.

## 2026-03-08 — Test Kairos d'un exemple `credit_balance_monitor`
- Objective: check whether a more arithmetic, non-finite-state example than `resettable_delay` is actually provable by the current Kairos toolchain before proposing it as a secondary example.
- First validated the command path against the existing `resettable_delay.kairos` test case.
- Observed an environment issue: Why3 was configured to call an outdated `z3` binary under the old opam switch path.
- Retained workaround for reliable testing:
  - invoke Kairos with `--prover-cmd /Users/fredericdabrowski/.opam/5.4.1+options/bin/z3`.
- First attempt:
  - tried to express a stronger assumption involving `prev bal + credit` in a node-level contract;
  - this failed at the parser level;
  - reason: in the current Kairos grammar, history terms such as `prev x` / `pre(x)` are admitted as `hexpr` atoms, but not as arbitrary arithmetic subexpressions.
- Successful variant:
  - created `credit_balance_monitor_candidate_v2.kairos`;
  - encoded the debit-balance side condition in transition guards instead of in a node-level temporal contract;
  - kept the invariant `m >= 0 /\ m = prev bal` in state `Run`;
  - verified the file successfully with:
    `DUNE_BUILD_DIR=/Users/fredericdabrowski/Repos/kairos/specv2/.kairos_build_credit_v2proof opam exec -- dune exec -- kairos --log-level quiet --prove --prover-cmd /Users/fredericdabrowski/.opam/5.4.1+options/bin/z3 /Users/fredericdabrowski/Repos/kairos/specv2/credit_balance_monitor_candidate_v2.kairos`
- Outcome:
  - the example is provable by Kairos;
  - the current syntax supports a good version of the example;
  - but the strongest contract formulation one would naturally want is limited by the current grammar of history expressions.

## 2026-03-08 — Added `credit_balance_monitor` to the paper
- Added a new secondary example to the `Instantiation and backend refinements` section of `conditional_safety_local_proofs.tex`.
- Positioning choice:
  - keep `resettable_delay` as the main pedagogical running example;
  - add `credit_balance_monitor` as a more data-intensive example that highlights the ability of the method to handle non-finite-state program semantics.
- Added the concrete Kairos code of the validated example directly in the paper.
- Added explanatory prose making the intended contrast explicit:
  - explicit-state model checking would need a separate abstraction argument because the balance ranges over unbounded integers;
  - the present reduction keeps the automaton side finite while leaving the program memory symbolic and relying on a local arithmetic invariant.
