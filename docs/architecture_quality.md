# Grille d'architecture et de qualité (Kairos)

Ce document propose une méthode simple et reproductible pour:
- décrire l'architecture de Kairos;
- mesurer sa qualité au fil des itérations;
- piloter les refactorings avec des critères objectifs.

## 1. Description d'architecture (socle documentaire)

### 1.1 Contexte (vue C4 niveau 1)
- Acteurs: utilisateur CLI, plugin VS Code/LSP, CI.
- Systèmes externes: Why3, Z3, Spot.
- Rôle de Kairos: réduire des contrats temporels en obligations locales.

### 1.2 Conteneurs (vue C4 niveau 2)
- `frontend`: parseur, AST.
- `middleend`: automates, produit, IR, enrichissements.
- `proof_export`: export kernel/kobj.
- `backends`: génération et preuve (Why3).
- `artifacts`: rendus texte/graphes.
- `pipeline`: orchestration globale des passes.

### 1.3 Composants clés (vue C4 niveau 3)
- Construction IR: `from_ast`.
- Enrichissements: `post`, `pre`, `temporal_lower`.
- Export: proof-kernel/kobj.
- Backend: compilation Why3 + soumission des VCs.

### 1.4 Flux de données (source de vérité)
1. AST
2. Automates require/ensures
3. Produit
4. Résumés locaux IR
5. Obligations locales
6. Décharge backend

### 1.5 Décisions d'architecture (ADR)
Créer une ADR pour chaque décision structurante:
- contexte;
- décision;
- alternatives rejetées;
- impacts (code, métriques, migration).

### 1.6 Invariants architecturaux
- Le Why généré est un artefact de compilation, pas une source de vérité.
- Pas d'instrumentation moniteur dans le backend Why.
- Les obligations doivent rester traçables depuis les résumés locaux IR.

## 2. Mesure de la qualité (tableau de bord)

## 2.1 Modularité
- Cycles de dépendances entre couches.
- Nombre de dépendances montantes (backend -> middleend interne, etc.).
- Nombre de modules à responsabilités multiples.

## 2.2 Maintenabilité
- Complexité cyclomatique par fichier.
- Duplication.
- Taille des fichiers (signal d'agrégation excessive).
- Churn + défauts sur les mêmes modules.

## 2.3 Fiabilité
- `ok_green`.
- `ko_false_green`.
- Stabilité des campagnes `without_call`.
- Régressions par passe (`from_ast`, `post`, `pre`, `temporal_lower`).

## 2.4 Performance
- Temps par phase:
  - Spot
  - Produit
  - IR
  - Génération Why3
  - VC + SMT
- Tailles:
  - états/arcs automates require/ensures;
  - états/transitions produit (total + vivant);
  - nombre de résumés locaux;
  - nombre d'obligations.

## 2.5 Traçabilité
- Proportion d'obligations rattachées à un résumé local identifiable.
- Cohérence entre artefacts de dump et données effectivement envoyées au backend.

## 2.6 Dette architecture
- Code mort identifié.
- APIs redondantes.
- Éléments mal placés par couche.
- Déviations temporaires documentées (avec date cible de retrait).

## 3. Rythme d'évaluation recommandé

## 3.1 Revue périodique (ex: mensuelle)
1. Générer les métriques automatiquement (script/CI).
2. Examiner 3 axes: correction, modularité, performance.
3. Ouvrir les actions d'amélioration (issues + ADR si nécessaire).

## 3.2 Seuils de base (à adapter)
- `ko_false_green = 0` (bloquant).
- Aucun cycle entre couches.
- Variance temporelle des campagnes dans une plage contrôlée.
- Traçabilité obligations -> IR maintenue à 100%.

## 4. Plan d'action type après revue

Pour chaque point critique:
1. Décrire le symptôme (métrique + module impacté).
2. Choisir un correctif minimal cohérent avec l'architecture cible.
3. Définir le critère d'acceptation mesurable.
4. Vérifier sur campagne complète avant merge.

---

Ce document sert de support opérationnel; il peut être complété par des
scripts de collecte automatiques et des tableaux de suivi versionnés.
