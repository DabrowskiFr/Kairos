From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
Import ListNotations.

From Kairos.core Require Import CoreStepSig.
From Kairos.obligations Require Import ObligationGenSig.
From Kairos.obligations Require Import OracleSemSig.

Set Implicit Arguments.

(* Canonical abstraction used by the formalization:
   obligations are discharged via Hoare triples attached to transitions.
   How transitions are encoded as ordinary program variables (e.g. state variable [st])
   is intentionally externalized. *)
Module Type TRANSITION_TRIPLE_GEN_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx).

  Parameter Transition : Type.
  Parameter HoareTriple : Type.

  Parameter transition_for_clause : E.Clause -> Transition.
  Parameter triples_of_transition : Transition -> list HoareTriple.

  Parameter clause_covered_by_transition : Transition -> E.Clause -> Prop.
  Axiom transition_for_clause_covers :
    forall cl,
      clause_covered_by_transition (transition_for_clause cl) cl.

  Parameter HoareValid : HoareTriple -> Prop.

  (* Local soundness: if all triples attached to the transition hold, then every
     clause covered by this transition is pointwise valid on reactive contexts. *)
  Axiom transition_triples_sound :
    forall tr cl u k,
      clause_covered_by_transition tr cl ->
      (forall ht, In ht (triples_of_transition tr) -> HoareValid ht) ->
      cl (C.ctx_at u k).
End TRANSITION_TRIPLE_GEN_SIG.

(* Abstract compilation layer: converts transition triples into an external VC format
   (e.g. Why3 program contracts that encode automaton states as ordinary variables). *)
Module Type EXTERNAL_TRIPLE_ENCODING_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (T : TRANSITION_TRIPLE_GEN_SIG C E).

  Parameter EncodedTriple : Type.
  Parameter encode : T.HoareTriple -> EncodedTriple.

  Parameter EncodedValid : EncodedTriple -> Prop.

  (* Semantic preservation of the compilation/encoding step. *)
  Axiom encode_sound :
    forall ht,
      EncodedValid (encode ht) ->
      T.HoareValid ht.
End EXTERNAL_TRIPLE_ENCODING_SIG.

Module Type EXTERNAL_ENCODED_CHECKER_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (T : TRANSITION_TRIPLE_GEN_SIG C E)
  (X : EXTERNAL_TRIPLE_ENCODING_SIG C E T).

  Parameter check : X.EncodedTriple -> bool.

  Axiom check_sound :
    forall et,
      check et = true ->
      X.EncodedValid et.

  (* Completeness is only required on generated clauses. *)
  Axiom check_complete_generated :
    forall cl ht,
      E.Generated cl ->
      In ht (T.triples_of_transition (T.transition_for_clause cl)) ->
      check (X.encode ht) = true.
End EXTERNAL_ENCODED_CHECKER_SIG.

Module MakeOracleSemFromTransitionTriples
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (T : TRANSITION_TRIPLE_GEN_SIG C E)
  (X : EXTERNAL_TRIPLE_ENCODING_SIG C E T)
  (K : EXTERNAL_ENCODED_CHECKER_SIG C E T X)
  <: ORACLE_SEM_SIG C E.

  Definition check_all (tr : T.Transition) : bool :=
    forallb (fun ht => K.check (X.encode ht)) (T.triples_of_transition tr).

  Definition Oracle (cl : E.Clause) : bool :=
    check_all (T.transition_for_clause cl).

  Definition ClauseValid (cl : E.Clause) : Prop :=
    forall u k, cl (C.ctx_at u k).

  Theorem Oracle_sound :
    forall cl,
      Oracle cl = true ->
      ClauseValid cl.
  Proof.
    intros cl Hor u k.
    unfold Oracle, check_all in Hor.
    pose proof
      (proj1
         (forallb_forall
            (fun ht => K.check (X.encode ht))
            (T.triples_of_transition (T.transition_for_clause cl)))
         Hor) as Hall.
    eapply T.transition_triples_sound.
    - exact (T.transition_for_clause_covers cl).
    - intros ht Hin.
      pose proof (Hall ht Hin) as Hchk.
      pose proof (K.check_sound (et := X.encode ht) Hchk) as Henc.
      exact (X.encode_sound (ht := ht) Henc).
  Qed.

  Theorem Oracle_complete :
    forall cl,
      E.Generated cl ->
      Oracle cl = true.
  Proof.
    intros cl Hgen.
    unfold Oracle, check_all.
    apply (proj2
      (forallb_forall
         (fun ht => K.check (X.encode ht))
         (T.triples_of_transition (T.transition_for_clause cl)))).
    intros ht Hin.
    eapply K.check_complete_generated.
    - exact Hgen.
    - exact Hin.
  Qed.

  Theorem clause_valid_pointwise :
    forall cl u k,
      ClauseValid cl ->
      cl (C.ctx_at u k).
  Proof.
    intros cl u k Hvalid.
    exact (Hvalid u k).
  Qed.
End MakeOracleSemFromTransitionTriples.
