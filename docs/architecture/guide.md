# Lire l'architecture de Kairos

Cette page est le point d'entree humain. Les diagrammes C4 et les graphes
`odep` sont utiles, mais ils ne doivent pas etre lus en premier.

## Ce Qu'il Faut Lire En Premier

Commencer par l'atlas des modules si tu cherches quel fichier ouvrir :

- `module_atlas.md`

Puis regarder cette carte simplifiee :

![Kairos architecture map](manual/kairos-map.svg)

Elle se lit de gauche a droite.

Le code important pour la correction est en vert :

- `lib/domain/core`
- `lib/domain/verification`
- `lib/domain/proof_export`

Le reste est necessaire pour faire tourner l'outil, mais ne doit pas definir
la semantique de verification :

- entrees utilisateur : CLI, LSP, frontend ;
- orchestration : snapshots, dumps, proof runs ;
- backends : Why3, Z3, Graphviz, text/rendering ;
- optimisations : sharing, slicing, grouping, batching.

## Chemin De Correction

La vue suivante montre seulement ce que Rocq doit comprendre :

![Kairos correction path](manual/correction-path.svg)

Le chemin de reference est :

```text
Core program model
  + supplied automata
  -> reference product
  -> Pre / Product_reachability / Post
  -> Temporal_lower
  -> Proof_kernel_types.node_ir
  -> Rocq
```

La regle de lecture est simple :

```text
Si une transformation change ce chemin, elle concerne la correction.
Si elle change seulement Why3, les dumps, le scheduling ou le rendu,
elle ne doit pas changer la sortie kernel.
```

## Table Des Blocs

| Bloc | Chemins | Role | Rocq |
| --- | --- | --- | --- |
| CLI / LSP | `bin/cli`, `bin/lsp` | Entrees utilisateur | Non |
| Frontend | `lib/adapters/in/kairos_lang` | Parse et elabore le langage de surface | Pas encore, sauf theoreme d'elaboration futur |
| Application | `lib/application` | Ports et use-cases | Non |
| Domain core | `lib/domain/core` | Syntaxe, modeles, IR, temporal layout | Oui |
| Verification kernel | `lib/domain/verification` | Produit programme x automates, obligations de reference | Oui, avec classification par passe |
| Proof export | `lib/domain/proof_export` | Vue d'echange proof-kernel pour diagnostics et Rocq futur | Oui |
| Runtime | `lib/adapters/out/runtime` | Snapshots, dumps, orchestration, proof runs | Non |
| Why3 backend | `lib/adapters/out/provers/why3` | Projection Why3 et choix backend | Non |
| Artifacts | `lib/adapters/out/artifacts` | Rendus texte/graphe/diagnostic | Non |
| External tools | `lib/adapters/out/external` | Spot, Why3, Z3, Graphviz, timing | Non |

## Classification Des Passes

| Passe | Classification | Pourquoi |
| --- | --- | --- |
| `Pre` | Reference | Ajoute les hypotheses necessaires aux pas produit |
| `Product_reachability` | Reference | Ajoute des obligations d'inatteignabilite/preservation, ne doit pas etre vu comme pruning |
| `Post` | Reference | Ajoute les obligations de sortie et de progression |
| `Temporal_lower` | Reference normalization | Rend explicites `pre/pre_k` via le layout temporel |
| `Formula_sharing` | Obligation-preserving optimization | Ne doit que partager physiquement des formules egales |

La version machine-lisible de cette table est :

- `docs/reference_pipeline_boundaries.json`

Le check associe est :

```sh
python3 scripts/check_reference_pipeline_boundaries.py
```

## Comment Utiliser Les Graphes Detaillees

Les vues automatiques sont dans `observed/`.

- `observed/dune-libraries.svg` : utile pour voir les dependances entre
  bibliotheques Dune.
- `observed/dune-modules.svg` : utile pour enqueter localement, mais trop
  dense comme vue de depart.

Les vues C4 Structurizr sont dans `structurizr/export/`.

- `structurizr-kairos-system-context.svg` : qui parle a Kairos.
- `structurizr-kairos-containers.svg` : decomposition intentionnelle.

Ces graphes servent a verifier une hypothese. Ils ne remplacent pas la carte
simplifiee ci-dessus.

## Questions A Poser Avant De Modifier Le Code

1. Est-ce que je change le chemin de correction ?
2. Est-ce que Rocq doit voir cette transformation ?
3. Est-ce une normalisation semantique ou une optimisation ?
4. Est-ce que cette optimisation peut changer la sortie proof-kernel ?
5. Est-ce que l'information appartient au programme, au produit, aux
   obligations, au backend, ou au reporting ?
6. Est-ce que le changement depend d'un outil externe ?

Si la reponse a 1 ou 2 est oui, le changement doit passer par le manifeste de
frontiere et les tests de stabilite kernel.
