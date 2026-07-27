# Audit de séparation du moteur d'exécution

Date : 2026-07-26

Statut : frontière implémentée.

Référence analysée : `b60df9b3`.

Le manifeste exécutable de la proposition est
`engine_runtime_split_manifest.json`.

## Résultat

La prochaine séparation utile n'est pas une nouvelle micro-bibliothèque. Elle
consiste à retirer du paquet `kairos` la composition concrète du moteur et à la
placer dans un paquet `kairos-engine-runtime`.

```text
kairos
  domaine + vérification + application + frontend Kairos

kairos-engine-contract
  données publiques sans dépendance

kairos-engine-runtime
  Kairos_engine.Api + composition + runtime + backends Kairos

kairos-cli / kairos-lsp
  clients du moteur d'exécution
```

Cette séparation est acyclique dans le graphe Dune observé. Elle n'a demandé
aucune modification des corps OCaml, des obligations, de Why3 ou de Rocq. La
réalisation est un changement de propriété Dune/opam et de noms publics de
bibliothèques, sans déplacement physique de fichiers.

Un raffinement ultérieur a déplacé la politique machine
`default_proof_jobs` de la micro-bibliothèque publique `kairos.shared` vers le
module privé `Runtime_defaults` de `kairos-engine-runtime`. L'alias
correspondant a été retiré de `Pipeline_types`. Ce raffinement ne change pas le
calcul effectué ; il place simplement la politique d'exécution dans son
propriétaire concret. Les volumes ci-dessous reflètent cet état, tandis que
l'ordre d'implémentation et son bilan de validation décrivent la séparation
initiale.

## Problème actuel

Les outils externes ont leurs propres paquets, mais `kairos.opam` dépend encore
de chacun d'eux :

- `kairos-spot-adapter` ;
- `kairos-why3-adapter` ;
- `kairos-graphviz-adapter` ;
- `kairos-telemetry` ;
- `kairos-automata-contract` ;
- `kairos-proof-contract` ;
- `kairos-engine-contract`.

La cause est structurelle :

```text
kairos.engine
  -> kairos.internal.composition
  -> kairos.internal.verification_runtime
  -> runtime automata / proof / diagnostics / outputs
  -> Spot / Why3 / Graphviz / telemetry
```

Les extractions précédentes ont donc rendu les outils autonomes, mais elles
n'ont pas encore rendu le noyau `kairos` installable sans la pile d'exécution.

## Méthode

L'analyse utilise le graphe généré par `odep` dans
`observed/dune-libraries.dot`, les stanzas Dune et les fichiers opam. Les
volumes sont les lignes physiques `.ml` et `.mli`.

Trois conditions définissent une frontière valide :

1. aucune bibliothèque conservée dans `kairos` ne dépend d'une bibliothèque
   déplacée dans `kairos-engine-runtime` ;
2. toutes les dépendances vers des outils externes sont du côté runtime ;
3. les dépendances du runtime vers le noyau sont unidirectionnelles.

Le graphe complet est acyclique. Après classification des 17 bibliothèques
candidates, les seules arêtes entrantes depuis l'extérieur de la cible sont :

```text
exécutable kairos -> kairos.engine
kairos-lsp.app    -> kairos.engine
```

Ce sont précisément les deux clients qui doivent dépendre du nouveau paquet.
Aucune bibliothèque conservée dans le noyau n'appelle le runtime.

## Volume et propriété

| Zone déplacée logiquement | Lignes OCaml |
| --- | ---: |
| `lib/engine` | 726 |
| `lib/composition` | 72 |
| `lib/adapters/out/runtime` | 5 726 |
| `lib/adapters/out/provers/why3` | 8 201 |
| `lib/adapters/out/artifacts` | 1 726 |
| `lib/adapters/out/codegen/c` | 1 128 |
| **Total runtime** | **17 579** |

Le périmètre principal conservé représente 16 708 lignes :

| Zone conservée dans `kairos` | Lignes OCaml |
| --- | ---: |
| `lib/domain` | 9 360 |
| `lib/application` | 2 559 |
| frontend Kairos | 4 789 |

Ces nombres mesurent la propriété de compilation, pas la taille de l'archive
du dépôt monolithique.

## Bibliothèques du paquet runtime

Le manifeste énumère les 17 bibliothèques et leurs futurs noms publics. Les
noms Dune internes restent inchangés. Cela préserve les chemins de modules
OCaml, notamment :

```text
Kairos_engine.Api
```

La bibliothèque racine change de nom Findlib :

```text
kairos.engine -> kairos-engine-runtime
```

Les bibliothèques privées installées suivent le préfixe du nouveau paquet :

```text
kairos.internal.runtime_core
  -> kairos-engine-runtime.internal.runtime_core
```

Cette rupture Findlib est intentionnelle. Conserver une bibliothèque de
compatibilité `kairos.engine` dans le paquet `kairos` obligerait celui-ci à
dépendre du runtime et annulerait le bénéfice recherché.

## Dépendances opam cibles

### `kairos`

Le paquet conserve le domaine, l'application, le frontend Kairos et Rocq. Il
retire les sept dépendances Kairos externes listées plus haut.

Le découpage révèle trois dépendances directes actuellement obtenues
transitivement et qui doivent devenir explicites :

- `fmt` et `logs` pour `kairos.domain_core` ;
- `sedlex` pour le frontend Kairos.

`menhir` reste nécessaire à la génération du parser et fournit la version
correspondante de `menhirLib`.

### `kairos-engine-runtime`

Le nouveau paquet dépend de :

- `kairos` et `kairos-engine-contract` ;
- contrats et adaptateurs Spot, Why3, Graphviz et télémétrie ;
- `why3` directement, car le compilateur Kairos vers Why3 importe son AST ;
- `yojson` pour les rapports de coût.

Le compilateur Kairos vers Why3 reste propriété du moteur Kairos. Son changement
de paquet ne prétend pas le rendre générique ou indépendant du domaine.

### Clients

`kairos-cli` et `kairos-lsp` remplacent leur dépendance opam sur `kairos` par
`kairos-engine-runtime`. Ils conservent leur dépendance directe sur
`kairos-engine-contract`, puisqu'ils nomment ses DTO dans leurs interfaces.

## Ordre d'implémentation réalisé

1. Ajouter `kairos-engine-runtime` à `dune-project` et créer son fichier opam.
2. Changer uniquement les `public_name` des 17 bibliothèques recensées.
3. Déplacer les dépendances opam externes de `kairos` vers le runtime et
   déclarer `fmt`, `logs`, `sedlex` directement dans `kairos`.
4. Migrer les dépendances opam du CLI et du LSP.
5. Affecter les tests du compilateur Why3 et du runtime automata au paquet
   runtime ; conserver les tests du domaine et du frontend dans `kairos`.
6. Régénérer les graphes observés et vérifier qu'aucune arête
   `kairos -> kairos-engine-runtime` n'existe.

Aucun fichier source ne doit être déplacé lors de cette première passe. Un
déplacement de répertoires mélangerait une décision de propriété de paquet
avec une réorganisation physique sans gain supplémentaire.

## Validation obligatoire

La validation doit être faite en quatre environnements de build distincts :

1. `kairos` seul, sans adaptateur Kairos autonome installé ;
2. `kairos-engine-runtime` contre une installation de `kairos` et des outils ;
3. `kairos-cli` contre le runtime installé ;
4. `kairos-lsp` contre le runtime installé.

Puis :

- `dune build @all` et `dune runtest` ;
- contrôles d'architecture, de couches et de format ;
- corpus complet : 44/44 verts, 46 invalides, 10 timeouts, 0 faux vert ;
- contrôle Git interdisant toute modification sous `rocq`, `lib/domain`,
  `lib/application` et `lib/adapters/in/kairos_lang`.

## Résultat de validation

La réalisation du 27 juillet 2026 satisfait ces critères :

- build isolé de `kairos` avec `--only-packages kairos` ;
- build isolé de `kairos-engine-runtime` contre les paquets installés ;
- builds isolés de `kairos-cli` et `kairos-lsp` contre le runtime installé ;
- suite Dune, architecture, couches, format, élaboration, génération C,
  historique de preuve et stabilité de référence : OK ;
- corpus : 44/44 verts, 46 invalides, 10 timeouts, 0 faux vert ;
- aucune modification `.ml`, `.mli`, Rocq, domaine, application ou frontend.

## Risques

### Dépendances transitives masquées

Le risque principal n'est pas sémantique : c'est l'oubli d'une dépendance opam
directe du noyau après retrait des adaptateurs. Le build isolé de `kairos` est
donc le premier critère, pas une vérification finale facultative.

### Rupture Findlib

Les consommateurs externes utilisant `(libraries kairos.engine)` devront
utiliser `(libraries kairos-engine-runtime)`. Le chemin OCaml
`Kairos_engine.Api` reste stable. Cette rupture doit être annoncée comme une
évolution de distribution.

### Faux découpage

Une façade de compatibilité située dans `kairos` ou une dépendance inverse du
noyau vers le runtime recréerait immédiatement le couplage. Les contrôles de
couches doivent l'interdire.

### Confusion de propriété scientifique

Déplacer le compilateur Why3 dans le paquet runtime ne change pas son statut :
il reste une projection sémantique propre à Kairos. Il ne devient ni un
contrat neutre, ni une source de vérité. La formalisation et les IR exportés
restent la référence.

## Décision recommandée

Le découpage est faisable, utile et acyclique. Il retire réellement les outils
externes des dépendances d'installation du noyau, contrairement à une nouvelle
micro-extraction.

Le manifeste a été implémenté uniquement par changements Dune/opam et
affectation des tests. Aucun corps de preuve, de domaine, de frontend ou de
backend n'a été modifié.
