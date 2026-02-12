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