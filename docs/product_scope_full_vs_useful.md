# Produit complet vs produit utile (sans casser l'IR)

## Contexte

Aujourd'hui, le pipeline construit un produit explicite large (états/arcs accessibles), puis la passe `post` filtre pour ne garder que la partie utile à la preuve dans `node.product_transitions`.

Le besoin est d'ajouter une option pour choisir entre:

- `Full`: construire le produit complet (comportement actuel, debug maximal).
- `Useful`: construire uniquement la partie utile à la preuve.

## Problème structurel actuel

La passe IR (`post`) ne consomme pas directement `analysis.exploration.steps`; elle recroise `programme × automates` et applique ensuite son propre filtrage.

Conséquence: même si on limitait la construction en amont, `post` pourrait réintroduire des pas "complets" en reconstruisant localement.

## Stratégie proposée

1. Introduire un mode global `product_scope = Full | Useful` (CLI + LSP), avec défaut `Full`.
2. Étendre l'analyse produit pour exposer explicitement la vue utilisée par l'IR:
   - `exploration_ir` (toujours disponible),
   - `exploration_full` (optionnelle, présente en mode `Full`).
3. Modifier `Post.product_transitions` pour consommer `analysis.exploration_ir.steps` au lieu de reconstruire le produit via les sorties automates.
4. Conserver `is_relevant_product_step` tel quel:
   - en mode `Full`, il garde le comportement actuel;
   - en mode `Useful`, il devient quasi idempotent (ne casse rien).
5. Ne pas changer `pre/invariant/lowering`: ces passes travaillent déjà sur `node.product_transitions`.
6. Adapter le rendu:
   - `--dump-product` affiche `exploration_full` si disponible, sinon `exploration_ir`;
   - ajouter dans le rendu (ou metadata) une indication `scope=full|useful`.

## Pourquoi cela ne casse pas l'IR

- La forme des contrats canoniques ne change pas (`product_contract`, `cases`, `safe_summary`, etc.).
- Seule la source des "steps candidats" change.
- Les passes aval continuent de lire les mêmes structures et les mêmes champs.

## Plan de migration en 2 étapes

1. **Étape A (safe)**: ajouter `product_scope` et câbler la config jusqu'au middle-end, sans changer le comportement (mode par défaut `Full`).
2. **Étape B (fonctionnelle)**: basculer `post` sur `analysis.exploration_ir.steps` et implémenter la construction `Useful`.

Cette séquence permet de valider progressivement:

- compatibilité CLI/LSP,
- stabilité des dumps actuels,
- non-régression des obligations générées.

## Critères d'acceptation

- En `Full`: mêmes contrats, mêmes VCs, mêmes résultats que la version actuelle.
- En `Useful`: mêmes VCs/résultats de preuve, produit plus petit (moins d'états/arcs).
- Les dumps indiquent clairement la portée (`full` vs `useful`).
- Les métriques `product_*` restent cohérentes avec le scope choisi.
