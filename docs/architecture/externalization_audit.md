# Audit d'externalisation de Kairos

Date : 2026-07-26

Statut : recommandations réalisées par les ADR-0016 à ADR-0019. Le protocole
et l'exécutable LSP appartiennent à `kairos-lsp`, tandis que `kairos-cli`
fournit l'exécutable `kairos`.

Les données publiques du moteur
appartiennent au paquet autonome `kairos-engine-contract`, et sa composition
concrète appartient à `kairos-engine-runtime`. Le paquet `kairos` conserve le
noyau sémantique, les interfaces applicatives et le frontend Kairos.

## Objet

Cet audit cherche les prochaines séparations qui diminuent réellement la
taille et le couplage du paquet principal Kairos. Il ne propose ni nouvelle
sémantique, ni modification du chemin de preuve, ni évolution de la
formalisation existante.

Le mot *externaliser* recouvre ici deux opérations distinctes :

1. donner à une fonction un paquet, des dépendances et des tests autonomes ;
2. déplacer physiquement ce paquet dans un autre dépôt ou processus.

Seule la première opération est nécessaire pour obtenir une frontière
d'architecture. La seconde reste une décision de distribution. Un paquet
autonome peut rester lié en processus : il n'impose ni IPC, ni sérialisation au
runtime.

## Méthode

L'analyse part de l'état propre au commit `d3dcb288`.

Les volumes sont des lignes physiques des fichiers `.ml` et `.mli`, commentaires
et interfaces compris. Ils sont reproductibles avec :

```sh
find <répertoire> -type f \( -name '*.ml' -o -name '*.mli' \) \
  -print0 | xargs -0 wc -l
```

Une extraction est évaluée suivant cinq critères :

- **autonomie technique** : dépendances limitées à des bibliothèques publiques
  et stables ;
- **propriété sémantique** : la fonction ne décide pas du sens des obligations
  Kairos ;
- **stabilité du contrat** : l'interface ne recopie pas les structures internes
  mouvantes ;
- **gain net** : la projection et le câblage ajoutés ne remplacent pas les
  lignes déplacées à coût égal ;
- **risque de correction** : la séparation ne change ni les objets de
  référence, ni les obligations, ni leur compilation.

Le « volume brut » ci-dessous est le code qui changerait de paquet. Ce n'est
pas une réduction du nombre total de lignes du dépôt. Le gain réel est la
réduction des dépendances et de la surface du paquet principal.

## État quantitatif

Le périmètre `lib` + `packages` contient 40 903 lignes OCaml :

| Zone | Lignes | Observation |
| --- | ---: | --- |
| `packages` déjà autonomes | 5 003 | Spot, Why3 runtime, Graphviz, télémétrie et contrats |
| `lib/domain/core` | 2 622 | syntaxe et IR Kairos |
| `lib/domain/verification` | 4 491 | produit, obligations et transformations |
| `lib/domain/proof_export` | 2 247 | projection du noyau de preuve |
| `lib/application` | 2 564 | ports et cas d'usage |
| frontend du langage Kairos | 4 789 | syntaxe, élaboration et conversion |
| renderers d'artefacts | 1 726 | projection métier et émission texte/DOT mélangées |
| backend C | 1 128 | projection directe du modèle Kairos vers C |
| compilation Kairos vers Why3 | 8 201 | projection sémantique et construction Why3 |
| orchestration runtime | 5 726 | composition des étapes et sorties |

La surface LSP ajoute 6 734 lignes hors de ce tableau :

| Sous-zone LSP | Lignes |
| --- | ---: |
| protocole et mapping applicatif sous `lib` | 2 254 |
| exécutable et transport sous `bin/lsp` | 4 480 |

Elle est actuellement livrée par le paquet `kairos`, qui dépend donc aussi de
`lsp` et `jsonrpc`.

## Classement

### A. Doit rester propriété de Kairos

Les zones suivantes définissent ou projettent le sens de la vérification. Les
déplacer derrière un contrat qui recopierait leurs types ne créerait aucune
indépendance.

| Zone | Motif |
| --- | --- |
| `domain/core` | vocabulaire sémantique actuel de Kairos |
| `domain/verification` | construction du produit et des obligations |
| `domain/proof_export` | projection alignée sur le noyau de preuve |
| frontend Kairos | sens du langage dédié et traduction vers le modèle |
| orchestration de référence | ordre et composition des passes de correction |
| compilation IR Kairos vers WhyML | choix d'encodage des obligations Kairos |
| projections vers les vues de diagnostic | interprétation des structures Kairos |

Le compilateur Why3 restant dans `lib/adapters/out/provers/why3` n'est pas
équivalent au runtime Why3 déjà extrait. Le runtime reçoit du WhyML neutre et
l'exécute. Le compilateur décide comment l'IR Kairos devient du WhyML. Le sortir
aujourd'hui imposerait soit d'exposer `Ir.node_ir`, soit de créer un second IR
de preuve aussi riche que lui. Dans les deux cas, le couplage serait seulement
déplacé.

### B. Renderers d'artefacts : extraction partielle seulement

Les 1 726 lignes de `lib/adapters/out/artifacts` ne forment pas un renderer
générique unique.

La séparation observée est :

```text
types Kairos
  -> sélection, fusion et nommage des états/transitions
  -> graphe prêt à afficher
  -> texte DOT
  -> appel externe à Graphviz
```

L'appel externe à Graphviz est déjà autonome. La partie strictement générique
encore dans Kairos est `automata_graph_dot.ml/.mli`, soit 203 lignes. Les autres
modules :

- choisissent les états et arêtes du produit ;
- fusionnent les pas suivant des propriétés du produit ;
- distinguent les états mauvais ;
- rendent les formules et historiques Kairos ;
- reconstruisent des transitions depuis `Verification_model` et `Ir`.

Extraire les 1 726 lignes en bloc exigerait un contrat qui reproduit
`Temporal_automata.node_data`, `Verification_model.node_model` et
`Ir.node_ir`. Ce contrat serait une fuite du modèle interne, pas une bonne
abstraction.

L'extraction des seules 203 lignes DOT est saine, mais son gain est trop faible
pour justifier à elle seule une nouvelle frontière. Elle pourra être absorbée
par le paquet Graphviz si un second consommateur apparaît.

### C. Backend C : candidat différé

Le backend C représente 1 128 lignes et dépend directement de
`kairos_domain_core`. Il traduit le modèle synchrone Kairos.

L'option analysée est de conserver ce backend comme projection propre au
langage Kairos.

Déplacer le backend actuel en lui donnant les types du domaine comme
dépendance ne le rendrait pas indépendant. Ce n'est donc pas la prochaine
étape.

### D. LSP : meilleur prochain candidat

Le LSP est un adaptateur d'entrée/sortie périphérique. Il ne définit ni le
produit, ni les obligations, ni leur compilation. Ses 6 734 lignes et ses
dépendances `lsp`/`jsonrpc` peuvent être retirées du paquet principal sans
changer le chemin CLI ou la correction.

Il existe un couplage à corriger avant le changement de paquet :

- `kairos_lsp_app` importe plusieurs types de `kairos_application` et le
  frontend ;
- `kairos_lsp_protocol` lit directement
  `Kairos_runtime_defaults.default_proof_jobs`.

La bonne frontière n'est pas un grand DTO copié depuis `Pipeline_types`. C'est
une façade applicative étroite, orientée cas d'usage :

```text
kairos-lsp
  -> Kairos_engine.run / parse / format / inspect
  -> résultats applicatifs stables
  -> noyau et adaptateurs Kairos
```

Le transport JSON-RPC, l'état des documents, les handlers et les vues LSP
restent entièrement dans `kairos-lsp`. Le paquet peut continuer à lier le
moteur Kairos en processus ; aucun protocole interprocessus n'est nécessaire.

## Comparaison des options

| Option | Volume brut déplacé | Effet sur le chemin actif | Contrat requis | Décision |
| --- | ---: | --- | --- | --- |
| paquet LSP séparé | 6 734 | retire une surface périphérique complète | façade applicative étroite | **réalisé** |
| paquet moteur concret | 17 502 | retire les outils externes du noyau installable | `kairos-engine-contract` | **réalisé** |
| backend C autonome | 1 128 | conserve une dépendance au modèle Kairos | exposition du modèle Kairos | conserver dans Kairos |
| émission DOT générique | 203 | aucun effet sémantique | graphe prêt à émettre | option opportuniste |
| tous les renderers | 1 726 | diagnostics seulement | miroir excessif des types métier | rejeter en bloc |
| compilateur WhyML | 8 201 | touche la projection des obligations | IR de preuve complet ou fuite de `Ir` | conserver dans Kairos |

## Séparation LSP réalisée

La frontière de distribution `kairos.engine` / `kairos-lsp` a été créée sans
déplacer les algorithmes :

1. inventorier les opérations réellement appelées par `bin/lsp` et
   `kairos_lsp_app` ;
2. définir une façade publique minimale pour ces opérations et leurs résultats ;
3. faire dépendre tout le LSP uniquement de cette façade, du contrat Graphviz
   déjà autonome et des bibliothèques LSP ;
4. créer un paquet `kairos-lsp` séparé ;
5. retirer `lsp` et `jsonrpc` des dépendances du paquet principal ;
6. conserver le même exécutable `kairos-lsp` et les mêmes tests de protocole.

Critères d'acceptation :

- aucun module LSP n'importe directement un module de domaine, de backend ou
  d'orchestration interne ;
- le paquet principal se construit sans `lsp` ni `jsonrpc` ;
- `kairos-lsp` se construit et se teste séparément ;
- CLI, tests d'architecture et corpus de validation restent inchangés ;
- aucune modification de la formalisation ou du chemin de preuve n'est
  nécessaire.

## Conclusion

Cette recommandation historique est réalisée : LSP, CLI, contrat moteur et
moteur concret ont maintenant leurs propres paquets. La fermeture acyclique
du moteur appartient à `kairos-engine-runtime`, conformément à
`engine_runtime_split_audit.md` et `engine_runtime_split_manifest.json`.
