+ inference invariants 
+ preferences / kairos/ config file
+ ast limited basis
* export pdf 
* use ocamldot (no, not usefl)
* mettre les éléments d'un même méthode qui passe au vert quand c'est bon. 
* dot en parallèle ? (pas nécessaire fait à la demande)
* problem performance ide
* refactoring
* avoid using textfile if no export

* ajouter aux transitions une transition par défaut qui va vers bad, pas de progrès = erreur.   
* problème gestion utf8
* Cas des branches skip du moniteur qui conduisent à rester dans le même état, il faudrait aller dans l'état bad car ça veut dire qu'on a un cas indéterminé.
* Quand pas de requires que mettre à la place? même question pour ensure.
* mode pur automate: les obligations OBC+ ne référencent pas explicitement les états A/G (projection sur les transitions programme), ce qui peut fusionner des cas distinguables et réduire la précision; envisager un conditionnement explicite par état produit pour la preuve.
* Documenter l’ajout de `W` (weak until) et la règle de validation a posteriori: `W` autorisé seulement en position positive (sinon rejet explicite).
