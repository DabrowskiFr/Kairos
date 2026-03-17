# MyTodo

Ce fichier liste les points mis de cote pendant la refonte IDE, avec un resume du probleme et des pistes concretes.

## 1) Selection Outline -> surlignage code incomplet

### Constat
- La selection d'une feuille dans `Outline` surligne le code uniquement pour les transitions de `Abstract Program`.
- Pour les autres feuilles (`Source` hors transitions abstraites, contrats, noeuds, etc.), aucun surlignage utile n'apparait.
- Une tentative de "fallback" ad hoc a ete ajoutee, mais elle n'est pas fiable et ne couvre pas les cas reels.

### Resume du probleme
- Le mapping "element Outline -> zone de texte a surligner" est partiel.
- Le chemin qui fonctionne (transitions de l'Abstract Program) doit etre pris comme reference.
- Les autres categories semblent manquer d'information d'origine exploitable (line/span/provenance) au moment de la navigation.

### Pistes possibles
- Analyser le flux qui marche de bout en bout:
  - extraction de l'element outline,
  - resolution de la cible (buffer + ligne/span),
  - application effective du highlight.
- Comparer structurellement ce flux avec les feuilles qui ne marchent pas (meme donnees? memes clefs? meme normalisation?).
- Unifier le modele de provenance pour tous les items d'outline:
  - stocker explicitement `target_buffer`, `line` ou idealement `span`,
  - eviter la reconstruction par recherche texte.
- S'appuyer sur les metadonnees deja disponibles dans les passes (AST/IR/Why spans) au lieu d'ajouter des heuristiques UI.
- Ajouter un mode debug temporaire dans l'IDE:
  - au clic outline, log de `kind`, `target`, `line`, `span`, item resolu,
  - verification visuelle de la correspondance avant surlignage.

### Critere de done
- Toute feuille selectionnable dans `Outline` declenche un positionnement et un surlignage correct dans le buffer correspondant.
- Aucune dependance a des regex/fallback ad hoc pour retrouver les elements.
- Comportement stable apres rebuild et sur plusieurs exemples (`delay`, `toggle`, `handoff`, etc.).

## 2) Mapping onglets automates <-> contenu affiche incorrect

### Constat
- Dans la fenetre dediee aux automates, certains onglets n'affichent pas le bon contenu.
- Le mapping attendu (`Guarantee`, `Assume`, `Product`, etc.) ne correspond pas toujours a ce qui est rendu.

### Resume du probleme
- La liaison entre onglet selectionne et buffer/graph associe est encore fragile.
- Il reste des incoherences entre nom d'onglet, source de donnees et rendu final.

### Pistes possibles
- Verifier explicitement le mapping central `tab_id -> (text_buffer, dot, image)` et le rendre declaratif.
- Supprimer tout fallback implicite qui reroute vers un autre automate quand une donnee est vide.
- Ajouter des assertions/logs au changement d'onglet:
  - onglet courant,
  - type d'automate attendu,
  - payload reel charge.
- Ajouter un test UI de non-regression minimal:
  - charger un exemple avec automates distincts,
  - verifier que chaque onglet affiche le bon automate.

### Critere de done
- Chaque onglet automates affiche uniquement le contenu correspondant a son type.
- Plus d'ambiguite entre onglets (pas de duplication involontaire).
- Comportement stable sur plusieurs exemples (`delay`, `toggle`, `handoff`).

## 3) Toolbar: bordures qui reapparaissent au survol

### Constat
- Les boutons de la toolbar sont quasi plats au repos, mais des bordures claires reapparaissent encore au `hover` sur certains boutons.

### Resume du probleme
- Les overrides CSS actuels ne couvrent pas tous les etats/precedences GTK3 du theme actif.
- Le rendu obtenu n'est pas encore conforme au style VSCode souhaite (icone seule, sans cadre visible).

### Pistes possibles
- Auditer les pseudo-etats GTK3 (`prelight`, `selected`, `backdrop`, `focus`) et leur priorite.
- Ajouter une classe dediee toolbar (ex: `toolbar-flat`) et cibler uniquement ces boutons avec des regles finales plus fortes.
- Verifier si certains styles proviennent de `relief`/style-context GTK et non du CSS uniquement.
- En dernier recours, remplacer les `button` par `event_box + image` pour controle total du rendu hover.

### Critere de done
- Aucun bouton toolbar n'affiche de bordure en etat `normal`, `hover`, `active`, `focus`.
- Le feedback visuel au survol reste present uniquement via fond leger.
