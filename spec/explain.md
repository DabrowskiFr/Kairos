# Explication de l'application

## Passe `contract_coherency`

### Résumé

La passe fait deux choses :

1. Elle valide l'usage de `pre_k` dans les contrats utilisateur (`requires` et `ensures`).
2. Elle ajoute des contraintes de cohérence dans les `ensures` des transitions.

### Validation statique de `pre_k`

Fonction : `validate_user_pre_k_definedness`.

- On calcule une borne minimale de pas atteignable par état depuis `init_state` (`min_step_by_state`).
- Pour une transition `t : src -> dst` :
  - chaque `pre_k(_, k)` dans un `require` doit vérifier `k <= min_step(src)`;
  - chaque `pre_k(_, k)` dans un `ensure` doit vérifier `k <= min_step(dst)`.
- En cas de violation, la passe échoue avec un message explicite (nœud, transition, phase, localisation).

Intuition :
- un `require` est évalué sur l'état source ;
- un `ensure` est évalué sur l'état destination.

### Cohérence des contrats

Fonction : `user_contracts_coherency`.

Pour chaque transition `t : src -> dst` :

- on prend `ens_conj = conj(ensures_user(t))` ;
- on regarde toutes les transitions `u` sortant de `dst` ;
- pour chaque `r` dans `requires_user(u)`, on génère :
  - `ens_conj -> shift(r)`

où `shift` est `shift_fo_backward_inputs` (décalage temporel sur les entrées).

Les formules générées sont ajoutées à `t.ensures` avec provenance `Coherency`.

### Cas `ensures(t)` vide

Si `ensures_user(t)` est vide, `conj(...) = None` et aucune implication de cohérence n'est ajoutée pour `t`.

### Entrée / sortie AST

- Entrée :
  - `node.trans` (`requires`/`ensures` utilisateur),
  - `node.init_state`,
  - `node.inputs`.
- Sortie :
  - transitions enrichies (`t.ensures`) ;
  - pas de structure `coherency_goals` séparée dans cette version.

### Exemple

Si :
- `t1 : S0 -> S1`, `ensures(t1) = [E]`
- `t2 : S1 -> S2`, `requires(t2) = [R]`

alors `t1.ensures` reçoit en plus : `E -> shift(R)`.

### Références code

- `lib/middle-end/contracts/contract_coherency.ml`
- `lib/middle-end/contracts/contracts_pass.ml`
