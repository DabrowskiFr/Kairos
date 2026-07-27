# Ordre de construction des paquets

Ce document décrit l'ordre de dépendance vérifié par
`.github/workflows/package-boundaries.yml` et
`scripts/check_package_boundaries.sh`.

## Graphe de distribution

```text
niveau 0
  kairos
  kairos-automata-contract
  kairos-proof-contract
  kairos-telemetry

niveau 1
  kairos-spot-adapter
    -> kairos-automata-contract

  kairos-why3-adapter
    -> kairos-proof-contract
    -> kairos-telemetry

niveau 2
  kairos-engine-runtime
    -> kairos
    -> contrats et adaptateurs des niveaux 0 et 1

niveau 3
  kairos-cli
    -> kairos-engine-runtime

  kairos-lsp
    -> kairos-engine-runtime
```

Les paquets d'un même niveau peuvent être construits en parallèle.
`kairos-automata-contract` et `kairos-proof-contract` restent séparés : leurs
modules et leurs consommateurs sont distincts, et une fusion ne réduirait pas
le nombre de frontières Findlib utiles.

Le contrat public du moteur n'est pas un paquet supplémentaire.
`Pipeline_types` est exposé par `Kairos_engine.Api.Contract` depuis
`kairos-engine-runtime`. L'appel du processus Graphviz appartient au même
paquet via `Kairos_engine.Graphviz_render`.

## Ce que vérifie la CI

La matrice contient quatre frontières :

| Entrée | Vérification |
| --- | --- |
| `core` | `kairos` construit avec `--only-packages kairos`, sans paquet Kairos externe installé dans un préfixe local |
| `runtime` | le runtime construit dans un répertoire neuf contre un `kairos` et des adaptateurs installés |
| `cli` | le CLI construit dans un répertoire neuf contre le runtime installé |
| `lsp` | le LSP construit dans un répertoire neuf contre le runtime installé |

Les prérequis sont installés dans un préfixe temporaire. Le paquet cible est
ensuite construit avec un `OCAMLPATH` pointant vers ce préfixe et un
`--build-dir` distinct. Il ne peut donc pas résoudre silencieusement une
bibliothèque d'un autre paquet depuis le build monolithique.

Un job séparé exécute `opam lint` sur les neuf manifestes. Les métadonnées
mainteneur, auteur, licence, projet, rapports de bugs et dépôt de développement
sont identiques pour tous les paquets du dépôt.

## Invariants

- `kairos` ne dépend d'aucun contrat ou adaptateur Kairos autonome ;
- le runtime dépend du noyau, jamais l'inverse ;
- CLI et LSP ne contournent pas `Kairos_engine.Api` ;
- `Kairos_engine.Api.Contract` désigne l'unique définition de
  `Pipeline_types` ;
- aucun paquet `kairos-engine-contract` ou `kairos-graphviz-adapter` ne
  réintroduit une copie du contrat ou un micro-adaptateur ;
- la CI ne modifie ni la formalisation, ni Rocq, ni les obligations ;
- un ajout de paquet ou une modification de l'ordre doit mettre à jour ce
  document, le script, la matrice et les contrôles d'architecture.

## Exécution locale

```sh
opam lint ./*.opam
scripts/check_package_boundaries.sh core
scripts/check_package_boundaries.sh runtime
scripts/check_package_boundaries.sh cli
scripts/check_package_boundaries.sh lsp
```
