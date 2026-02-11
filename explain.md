# Explication de l'application

## Passe `contract_coherency`

### TL;DR

La passe `contract_coherency` vérifie la cohérence temporelle entre contrats utilisateur d'un nœud.
Elle ne modifie pas le code exécutable des transitions.
Elle génère des obligations logiques et les stocke dans `node.attrs.coherency_goals`.
Ces obligations sont ensuite visibles en OBC+ et émises en goals dédiés en Why3.

### Ce que la passe fait

- Pour chaque transition `t`, elle calcule `conj(ensures(t))`.
- Elle récupère les transitions partant de `t.dst`.
- Pour chaque `require` successeur `r`, elle ajoute le goal :
  - `conj(ensures(t)) -> shift(r)`
- `shift` correspond à `shift_fo_backward_inputs` (alignement temporel des entrées).

### Ce que la passe ne fait pas

- Elle ne modifie pas les gardes ou actions de transitions.
- Elle n'injecte pas ces contraintes dans les `ensures` des transitions.
- Elle ne crée pas de WP supplémentaire dans le code `step`.

### Règle formelle

Pour toute transition `t : src -> dst`, et toute transition `u` telle que `u.src = dst`, pour tout `r` dans `requires(u)` :

- goal de cohérence : `conj(ensures(t)) -> shift(r)`
- si `ensures(t)` est vide, `conj(ensures(t))` est interprété comme `true`, donc le goal devient `shift(r)`.

### Cas initial

Le démarrage est traité sans transition `_boot` explicite :

- on prend les transitions sortant de `init_state`,
- leurs `requires` deviennent des goals initiaux avec antécédent `true` et décalage temporel des entrées.

Implémentation :

- `Ast_utils.requires_from_state_fn n n.init_state`

### Algorithme (implémentation actuelle)

1. Construire `is_input` avec `Ast_utils.is_input_of_node`.
2. Construire le lookup des transitions sortantes avec `Ast_utils.transitions_from_state_fn`.
3. Pour chaque transition `t` :
   - calculer `conj(ensures(t))`,
   - récupérer les successeurs depuis `t.dst`,
   - générer les implications vers leurs `requires` (après `shift`).
4. Ajouter les goals initiaux depuis `init_state`.
5. Fusionner avec l'existant via `Ast_utils.add_new_coherency_goals` :
   - déduplication,
   - origine `Coherency`.

### Entrée / sortie AST

- Entrée :
  - `node.trans` (avec `requires`/`ensures` utilisateur),
  - `node.init_state`,
  - `node.inputs` (pour `shift`).
- Sortie :
  - `node.attrs.coherency_goals` enrichi,
  - transitions inchangées.

### Exemple minimal

Si `t1 : S0 -> S1` avec `ensures(t1) = [E]`, et `t2 : S1 -> S2` avec `requires(t2) = [R]`, alors :

- goal généré : `E -> shift(R)`

Si `t0` sort de `init_state` avec `requires(t0) = [R0]`, alors :

- goal initial généré : `true -> shift(R0)`

### Sortie backend

- OBC+ : goals visibles dans la section `coherency goals`.
- Why3 : goals dédiés (séparés des obligations WP du `step`).

### Points d'attention

- L'ordre des transitions peut influencer l'ordre d'affichage des goals (pas leur sens logique).
- La déduplication se fait sur la formule logique (`fo`) avant wrapping provenance.
- Si `ensures(t)` est vide, les goals sont quand même générés avec antécédent `true`.

### Références code

- `lib/middle-end/contracts/contract_coherency.ml`
- `lib/common/ast/ast_utils.ml`
- `lib/middle-end/contracts/contracts_pass.ml`
