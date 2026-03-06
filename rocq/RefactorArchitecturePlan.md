# Refactor Architecture Plan (Rocq -> Application)

## Objectif
Utiliser la formalisation Rocq comme contrat d'architecture pour refactorer l'application sans regression semantique (correction vis-a-vis des formules LTL et du decalage temporel).

## Arborescence cible
```text
rocq/
  core/
    CoreStepSig.v
    CoreStepLaws.v
  monitor/
    MonitorSig.v
    InputMonitor.v
    GuaranteeMonitor.v
    ProductMonitor.v
  logic/
    FOLanguageSig.v
    ShiftSpecSig.v
  obligations/
    ObligationGenSig.v
    OracleSig.v
  refinement/
    RefinementSig.v
    ShiftRefinement.v
  kernels/
    ShiftKernel.v
    SafetyKernel.v
  instances/
    DelayIntInstance.v
    KairosCurrentBridge.v
  integration/
    EndToEndTheorem.v
```

## Mapping avec l'existant
- `/Users/fredericdabrowski/Repos/kairos/rocq/KairosOracle.v` -> source monolithique de reference.
- `/Users/fredericdabrowski/Repos/kairos/rocq/KairosModularArchitecture.v` -> noyau modulaire actuel.
- `/Users/fredericdabrowski/Repos/kairos/rocq/KairosModularIntegration.v` -> bridge actuel vers les definitions concretes.
- `/Users/fredericdabrowski/Repos/kairos/rocq/KairosRefactorBlueprint.v` -> blueprint des interfaces cible pour la refonte.

## Contrats a imposer a l'implementation
1. `CoreStep`: la transition d'un tick est explicite et relie `cfg_at`, `ctx_at`, `run_trace`.
2. `InputAdmissibility`: `AvoidA -> InputOk` est un lemme obligatoire.
3. `ShiftSpec`: correction du shift conditionnee par `InputOk`.
4. `ObligationGen`: toute obligation critique est tracable via `GeneratedBy`.
5. `Oracle`: `sound` + `complete` sur l'espace d'obligations generees.
6. `Refinement`: preuve que les objets concrets (AST/prev_k) raffinent les objets abstraits.

## Checkpoints de migration (ordre recommande)
1. Isoler `CoreStep` et prouver les lois locales (pas de dependance oracle).
2. Extraire `A/G` + produit dans `monitor/*`.
3. Connecter `ShiftSpec` a l'admissibilite d'entree.
4. Brancher generation + oracle avec traces d'origine.
5. Ajouter `RefinementSig` et relier l'implementation concrete (prev_k, transform).
6. Reprouver le theoreme end-to-end sur le pipeline modulaire.

## Critere de "pret pour refactor applicatif"
- Chaque passe applicative a une interface Rocq homologue.
- Chaque transformation concrete a une preuve de refinement vers l'abstraction.
- Toute hypothese residuelle est localisee dans un module d'instance (pas dans les kernels).
