# Objectif + Methodologie (Etude comparative article LTL / Kairos)

## Objectif
Produire une etude comparative poussee entre l'article
`Verification de proprietes LTL sur des programmes C par generation d'annotations`
(N. Stouls, J. Groslambert, 2011) et l'architecture actuelle de Kairos, en
particulier:
- le produit explicite `programme x A x G`,
- la generation d'obligations locales,
- la projection vers un backend externe,
- la frontiere entre noyau prouve et hypotheses externes.

## Methodologie
1. Identifier dans l'article les objets structurants effectivement exploitables:
   - compilation LTL -> automate,
   - etats d'automate synchronises avec une execution,
   - annotations generees,
   - hypothese de validation externe.
2. Relire les fichiers centraux du chantier Kairos:
   - `rocq/KairosOracle.v`,
   - `rocq/PROOF_STATUS.md`,
   - `rocq/README.md`,
   - `spec/rocq_oracle_model.tex`,
   - middle-end OCaml produit / obligations.
3. Comparer selon des axes explicites:
   - objet semantique central,
   - unite de verification,
   - forme des obligations,
   - relation automate / execution,
   - role du backend externe,
   - statut de la preuve interne.
4. Distinguer systematiquement:
   - les convergences de fond,
   - les divergences de modelisation,
   - les opportunites concretes pour Kairos,
   - les points ou l'article ne couvre pas le besoin Kairos.
5. Consigner le resultat dans un document de synthese reutilisable pour les
   choix d'architecture et de documentation.

## Resultat attendu
Un document qui ne soit ni un simple resume de l'article, ni un simple etat du
depot, mais une comparaison argumentee permettant de repondre a:
- en quoi Kairos est deja proche de cette ligne de travail;
- en quoi Kairos va plus loin;
- en quoi l'article suggere encore des simplifications ou clarifications utiles.
