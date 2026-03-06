From Stdlib Require Import Arith.Arith.

Set Implicit Arguments.

Module Type PROGRAM_SEM_SIG.
  Parameter InputVal OutputVal Mem State : Type.
  Definition stream (A : Type) : Type := nat -> A.

  Parameter StepCtx : Type.
  Parameter ctx_at : stream InputVal -> nat -> StepCtx.
  Parameter run_trace : stream InputVal -> stream (InputVal * OutputVal).
End PROGRAM_SEM_SIG.

Module Type SAFETY_SIG.
  Parameter Obs : Type.
  Parameter Q : Type.
  Parameter q0 : Q.
  Parameter bad : Q.
  Parameter delta : Q -> Obs -> Q.

  Definition stream (A : Type) : Type := nat -> A.

  Fixpoint aut_state_at (w : stream Obs) (k : nat) : Q :=
    match k with
    | O => q0
    | S n => delta (aut_state_at w n) (w n)
    end.

  Definition avoids_bad (w : stream Obs) : Prop :=
    forall k, aut_state_at w k <> bad.
End SAFETY_SIG.

Module Type OBLIGATION_ENGINE_SIG.
  Parameter StepCtx : Type.
  Definition Obligation : Type := StepCtx -> Prop.

  Parameter origin : Type.
  Parameter GeneratedBy : origin -> Obligation -> Prop.

  Definition Generated (obl : Obligation) : Prop :=
    exists o, GeneratedBy o obl.
End OBLIGATION_ENGINE_SIG.

Module Type INPUT_OK_LINK_SIG.
  Parameter InputVal : Type.
  Definition stream (A : Type) : Type := nat -> A.
  Parameter InputOkA : stream InputVal -> nat -> Prop.
  Parameter InputOkL : stream InputVal -> nat -> Prop.
  Axiom input_okA_implies_input_okL :
    forall u k, InputOkA u k -> InputOkL u k.
End INPUT_OK_LINK_SIG.

Module Type HISTORY_LOGIC_SIG.
  Parameter InputVal OutputVal : Type.
  Parameter StepCtx : Type.
  Parameter ctx_at : (nat -> InputVal) -> nat -> StepCtx.
  Parameter InputOk : (nat -> InputVal) -> nat -> Prop.

  Parameter FO : Type.
  Parameter eval_fo : StepCtx -> FO -> Prop.
  Parameter shift_fo : nat -> FO -> FO.

  Axiom shift_fo_correct_if_input_ok :
    forall d u k phi,
      InputOk u k ->
      eval_fo (ctx_at u k) (shift_fo d phi) <-> eval_fo (ctx_at u (k + d)) phi.
End HISTORY_LOGIC_SIG.

Module MakeCorrectness
    (P : PROGRAM_SEM_SIG)
    (A : SAFETY_SIG with Definition Obs := P.InputVal)
    (G : SAFETY_SIG with Definition Obs := (P.InputVal * P.OutputVal)%type)
    (L : HISTORY_LOGIC_SIG
         with Definition InputVal := P.InputVal
         with Definition OutputVal := P.OutputVal
         with Definition StepCtx := P.StepCtx
         with Definition ctx_at := P.ctx_at)
    (E : OBLIGATION_ENGINE_SIG with Definition StepCtx := P.StepCtx)
    (R : INPUT_OK_LINK_SIG
         with Definition InputVal := P.InputVal
         with Definition InputOkA := (fun u k => A.aut_state_at u k <> A.bad)
         with Definition InputOkL := L.InputOk).

  Definition InputOkA (u : P.stream P.InputVal) (k : nat) : Prop :=
    A.aut_state_at u k <> A.bad.

  Definition AvoidA (u : P.stream P.InputVal) : Prop :=
    A.avoids_bad u.

  Definition AvoidG (u : P.stream P.InputVal) : Prop :=
    G.avoids_bad (P.run_trace u).

  Lemma avoids_bad_A_implies_InputOkA :
    forall u, AvoidA u -> forall k, InputOkA u k.
  Proof.
    intros u HA k.
    unfold AvoidA, InputOkA in *.
    exact (HA k).
  Qed.

  Lemma shift_one_step_if_InputOkA :
    forall u k phi,
      InputOkA u k ->
      L.eval_fo (P.ctx_at u k) (L.shift_fo 1 phi) <->
      L.eval_fo (P.ctx_at u (S k)) phi.
  Proof.
    intros u k phi Hok.
    pose proof (R.input_okA_implies_input_okL (u := u) (k := k) Hok) as HokL.
    rewrite (@L.shift_fo_correct_if_input_ok 1 u k phi HokL).
    rewrite Nat.add_1_r.
    reflexivity.
  Qed.

  Theorem shifted_formula_transfers_to_successor_under_A :
    forall u phi,
      AvoidA u ->
      forall k,
        L.eval_fo (P.ctx_at u k) (L.shift_fo 1 phi) ->
        L.eval_fo (P.ctx_at u (S k)) phi.
  Proof.
    intros u phi HA k Hk.
    pose proof (avoids_bad_A_implies_InputOkA (u := u) HA k) as Hok.
    pose proof (shift_one_step_if_InputOkA (u := u) (k := k) phi Hok) as Hshift.
    exact ((proj1 Hshift) Hk).
  Qed.
End MakeCorrectness.
