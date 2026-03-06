Require Import integration.ThreeLayerArchitecture.
Require Import logic.LTLPredicate.
Require Import monitor.MonitorSig.

Set Implicit Arguments.

Module Type CONTRACT_COMPILER_SIG
  (P : PROGRAM_LAYER_SIG)
  (Amon : MONITOR_SIG with Definition Obs := P.InputVal)
  (Gmon : MONITOR_SIG with Definition Obs := (P.InputVal * P.OutputVal)%type)
  (LA : LTL_PREDICATE_SIG with Definition Obs := P.InputVal)
  (LG : LTL_PREDICATE_SIG with Definition Obs := (P.InputVal * P.OutputVal)%type).

  Parameter ContractA : Type.
  Parameter ContractG : Type.

  Parameter contractA_of_program : ContractA.
  Parameter contractG_of_program : ContractG.

  Parameter compile_A : ContractA -> LA.Formula.
  Parameter compile_G : ContractG -> LG.Formula.

  Axiom compile_A_sound_complete :
    forall u,
      Amon.avoids_bad u <-> LA.sat (compile_A contractA_of_program) u.

  Axiom compile_G_sound_complete :
    forall w,
      Gmon.avoids_bad w <-> LG.sat (compile_G contractG_of_program) w.
End CONTRACT_COMPILER_SIG.
