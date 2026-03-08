From Stdlib Require Import Arith.Arith.
From Kairos Require Import KairosOracle.
From Kairos Require Import KairosModularArchitecture.

Set Implicit Arguments.

Module Type KAIROS_ORACLE_INSTANCE_SIG.
  Parameter InputVal OutputVal Mem State : Type.

  Parameter Paut : KairosOracleModel.ProgramAutomaton InputVal OutputVal Mem State.
  Parameter prog_select : State -> Mem -> InputVal -> KairosOracleModel.Trans Paut.
  Parameter init_state : State.
  Parameter init_mem : Mem.

  Parameter A_aut : KairosOracleModel.SafetyAutomaton InputVal.
  Parameter G_aut : KairosOracleModel.SafetyAutomaton (InputVal * OutputVal).
  Parameter A_aut_e : KairosOracleModel.SafetyAutomatonEdges A_aut.
  Parameter G_aut_e : KairosOracleModel.SafetyAutomatonEdges G_aut.
  Parameter select_A :
    KairosOracleModel.q A_aut -> InputVal -> KairosOracleModel.Edge A_aut_e.
  Parameter select_G :
    KairosOracleModel.q G_aut ->
    (InputVal * OutputVal) ->
    KairosOracleModel.Edge G_aut_e.
  Parameter node_inv :
    State -> KairosOracleModel.StepCtx Mem State A_aut G_aut -> Prop.

  Parameter FO : Type.
  Parameter eval_fo : KairosOracleModel.StepCtx Mem State A_aut G_aut -> FO -> Prop.
  Parameter shift_fo : nat -> FO -> FO.
  Parameter node_inv_fo : State -> FO.
  Axiom node_inv_fo_correct :
    forall s ctx, eval_fo ctx (node_inv_fo s) <-> node_inv s ctx.

  Axiom shift_fo_correct_if_input_ok :
    forall d u k phi,
      KairosOracleModel.InputOk A_aut_e select_A u k ->
      eval_fo
        (KairosOracleModel.ctx_at
           Paut init_state init_mem prog_select
           A_aut_e G_aut_e select_A select_G u k)
        (shift_fo d phi)
      <->
      eval_fo
        (KairosOracleModel.ctx_at
           Paut init_state init_mem prog_select
           A_aut_e G_aut_e select_A select_G u (k + d))
        phi.
End KAIROS_ORACLE_INSTANCE_SIG.

Module KairosModularBridge (X : KAIROS_ORACLE_INSTANCE_SIG).

  Module PConcrete <: PROGRAM_SEM_SIG.
    Definition InputVal := X.InputVal.
    Definition OutputVal := X.OutputVal.
    Definition Mem := X.Mem.
    Definition State := X.State.
    Definition stream (A : Type) : Type := nat -> A.

    Definition StepCtx := KairosOracleModel.StepCtx Mem State X.A_aut X.G_aut.
    Definition ctx_at :=
      KairosOracleModel.ctx_at
        X.Paut X.init_state X.init_mem X.prog_select
        X.A_aut_e X.G_aut_e X.select_A X.select_G.
    Definition run_trace :=
      KairosOracleModel.run_trace
        X.Paut X.init_state X.init_mem X.prog_select.
  End PConcrete.

  Module AConcrete <: SAFETY_SIG with Definition Obs := PConcrete.InputVal.
    Definition Obs := PConcrete.InputVal.
    Definition stream (A : Type) : Type := nat -> A.
    Definition Q := KairosOracleModel.q X.A_aut.
    Definition q0 := KairosOracleModel.q0 X.A_aut.
    Definition bad := KairosOracleModel.bad X.A_aut.
    Definition delta (qa : Q) (i : Obs) : Q :=
      KairosOracleModel.delta_A X.A_aut_e X.select_A qa i.

    Fixpoint aut_state_at (w : stream Obs) (k : nat) : Q :=
      match k with
      | O => q0
      | S n => delta (aut_state_at w n) (w n)
      end.

    Definition avoids_bad (w : stream Obs) : Prop :=
      forall k, aut_state_at w k <> bad.
  End AConcrete.

  Module GConcrete <: SAFETY_SIG with Definition Obs := (PConcrete.InputVal * PConcrete.OutputVal)%type.
    Definition Obs := (PConcrete.InputVal * PConcrete.OutputVal)%type.
    Definition stream (A : Type) : Type := nat -> A.
    Definition Q := KairosOracleModel.q X.G_aut.
    Definition q0 := KairosOracleModel.q0 X.G_aut.
    Definition bad := KairosOracleModel.bad X.G_aut.
    Definition delta (qg : Q) (io : Obs) : Q :=
      KairosOracleModel.delta_G X.G_aut_e X.select_G qg io.

    Fixpoint aut_state_at (w : stream Obs) (k : nat) : Q :=
      match k with
      | O => q0
      | S n => delta (aut_state_at w n) (w n)
      end.

    Definition avoids_bad (w : stream Obs) : Prop :=
      forall k, aut_state_at w k <> bad.
  End GConcrete.

  Module LConcrete <: HISTORY_LOGIC_SIG
      with Definition InputVal := PConcrete.InputVal
      with Definition OutputVal := PConcrete.OutputVal
      with Definition StepCtx := PConcrete.StepCtx
      with Definition ctx_at := PConcrete.ctx_at.
    Definition InputVal := PConcrete.InputVal.
    Definition OutputVal := PConcrete.OutputVal.
    Definition StepCtx := PConcrete.StepCtx.
    Definition ctx_at := PConcrete.ctx_at.
    Definition InputOk (u : nat -> InputVal) (k : nat) : Prop :=
      KairosOracleModel.InputOk X.A_aut_e X.select_A u k.

    Definition FO := X.FO.
    Definition eval_fo := X.eval_fo.
    Definition shift_fo := X.shift_fo.

    Theorem shift_fo_correct_if_input_ok :
      forall d u k phi,
        InputOk u k ->
        eval_fo (ctx_at u k) (shift_fo d phi) <-> eval_fo (ctx_at u (k + d)) phi.
    Proof.
      intros d u k phi Hok.
      apply X.shift_fo_correct_if_input_ok.
      exact Hok.
    Qed.
  End LConcrete.

  Module EConcrete <: OBLIGATION_ENGINE_SIG with Definition StepCtx := PConcrete.StepCtx.
    Definition StepCtx := PConcrete.StepCtx.
    Definition Clause : Type := StepCtx -> Prop.
    Definition origin := KairosOracleModel.origin.
    Definition GeneratedBy (o : origin) (cl : Clause) : Prop :=
      @KairosOracleModel.GeneratedBy
        X.InputVal
        X.OutputVal
        X.Mem
        X.State
        X.Paut
        X.init_state
        X.A_aut
        X.G_aut
        X.A_aut_e
        X.G_aut_e
        X.select_A
        X.select_G
        X.node_inv
        X.FO
        X.eval_fo
        X.shift_fo
        X.node_inv_fo
        o cl.
    Definition Generated (cl : Clause) : Prop :=
      exists o, GeneratedBy o cl.
  End EConcrete.

  Module RConcrete <: INPUT_OK_LINK_SIG
      with Definition InputVal := PConcrete.InputVal
      with Definition InputOkA := (fun u k => AConcrete.aut_state_at u k <> AConcrete.bad)
      with Definition InputOkL := LConcrete.InputOk.
    Definition InputVal := PConcrete.InputVal.
    Definition stream (A : Type) : Type := nat -> A.
    Definition InputOkA (u : nat -> InputVal) (k : nat) : Prop :=
      AConcrete.aut_state_at u k <> AConcrete.bad.
    Definition InputOkL (u : nat -> InputVal) (k : nat) : Prop :=
      LConcrete.InputOk u k.

    Theorem input_okA_implies_input_okL :
      forall u k, InputOkA u k -> InputOkL u k.
    Proof.
      intros u k H.
      exact H.
    Qed.
  End RConcrete.

  Module C := MakeCorrectness PConcrete AConcrete GConcrete LConcrete EConcrete RConcrete.

  Lemma A_aut_state_at_eq :
    forall u k,
      AConcrete.aut_state_at u k =
      KairosOracleModel.aut_state_at_A X.A_aut_e X.select_A u k.
  Proof.
    intros u k.
    induction k as [|n IH].
    - reflexivity.
    - simpl.
      rewrite IH.
      reflexivity.
  Qed.

  Lemma avoids_bad_A_to_CAvoidA :
    forall u,
      KairosOracleModel.avoids_bad_A X.A_aut_e X.select_A u ->
      C.AvoidA u.
  Proof.
    intros u HA k.
    unfold C.AvoidA, AConcrete.avoids_bad.
    rewrite A_aut_state_at_eq.
    exact (HA k).
  Qed.

  Theorem modular_shifted_formula_transfers_to_successor_under_A :
    forall u phi,
      KairosOracleModel.avoids_bad_A X.A_aut_e X.select_A u ->
      forall k,
        X.eval_fo
          (KairosOracleModel.ctx_at
             X.Paut X.init_state X.init_mem X.prog_select
             X.A_aut_e X.G_aut_e X.select_A X.select_G u k)
        (X.shift_fo 1 phi) ->
        X.eval_fo
          (KairosOracleModel.ctx_at
             X.Paut X.init_state X.init_mem X.prog_select
             X.A_aut_e X.G_aut_e X.select_A X.select_G u (S k))
        phi.
  Proof.
    intros u phi HA k Hk.
    pose proof (avoids_bad_A_to_CAvoidA (u := u) HA) as HA'.
    exact ((C.shifted_formula_transfers_to_successor_under_A (u := u) (phi := phi) HA') k Hk).
  Qed.

End KairosModularBridge.
