# Remarques de relecture traitées pour `spec/rocq_oracle_model.tex`

Lot traite le 2026-03-07.

Ce fichier archive le troisieme lot de remarques integrees dans le papier
mathematique. Le tampon courant `spec/ROCQ_PAPER_REMARKS.md` a ensuite ete
reinitialise.

## Themes traites dans ce lot

- amelioration de la lisibilite de `ctx(u,k)`:
  - remplacement du n-uplet plat par une presentation factorisee
    `source / observation / cible`;
  - motivation explicite du contexte local avant sa definition;
- introduction plus nette des notions de:
  - tick;
  - tick concret;
  - pas abstrait du produit;
  - relation de matching entre execution concrete et pas abstrait;
- clarification de `delay_int`:
  - distinction explicite entre exploration statique du produit et execution
    concrete;
  - presentation du pas dangereux;
  - presentation de l'obligation locale effectivement generee;
  - explication du role de cette obligation pour interdire l'acces a
    `Mon_bad`;
- instanciation immediate de la vue procedurale sur `delay_int` avant le schema
  general;
- reecriture de l'algorithme conceptuel pour montrer des obligations concretes
  generees, et non plus seulement des categories nominales;
- reecriture de la section `Origines abstraites` pour en faire une
  classification derivee des regles de generation;
- reecriture de la `Chaine de preuve`:
  - hypotheses explicites;
  - enonces plus formels;
  - esquisses de preuve alignees sur `KairosOracle.v`;
  - suppression des formulations narratives du type "supposons que...";
- reecriture de l'abstract sans formules;
- reecriture de l'introduction dans un style plus proche d'un article de
  recherche, avec probleme, difficulte, idee cle et positionnement;
- passe de conformite contre la specification Rocq sous-jacente:
  - `StepCtx`;
  - `product_step_realizes_at`;
  - `gen_from_product_step`;
  - `GeneratedBy`;
  - `bad_local_step_if_G_violated`;
  - `generation_coverage`.

## Validation associee

- `opam exec --switch=5.4.1+options -- latexmk -pdf -interaction=nonstopmode -outdir=spec spec/rocq_oracle_model.tex`
  - OK
  - warnings residuels mineurs de mise en page uniquement
