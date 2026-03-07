Require Import integration.ThreeLayerArchitecture.
Require Import integration.ThreeLayerFromCore.
Require Import obligations.OracleSemSig.
Require Import obligations.TransitionTriplesBridge.

Set Implicit Arguments.

(* Historical filename kept for compatibility.

   Preferred reading/API:
   - module type [VALIDATION_ASSUMPTIONS]
   - modules [MakeValidationAssumptionsFromOracleSem] and
     [MakeValidationAssumptionsFromTransitionTriples]

   Legacy compatibility names:
   - [EXTERNAL_VALIDATION_ASSUMPTIONS]
   - [MakeExternalValidationAssumptionsFromOracleSem]
   - [MakeExternalValidationAssumptionsFromTransitionTriples] *)

(*
  Unique interface for external assumptions used by the final automata
  correctness theorem.

  At this level the final theorem only needs semantic facts about generated
  clauses:
  - every generated clause is accepted by the external validation stack;
  - every accepted clause is semantically valid on concrete ticks.

  The concrete path "generated clauses -> transition Hoare bundles -> encoded
  VCs -> external checker" is intentionally factored below via helper functors.
*)
Module Type EXTERNAL_VALIDATION_ASSUMPTIONS
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_FROM_PROVED_SIG P).

  Parameter Oracle : K.Clause -> bool.

  Axiom oracle_sound_true :
    forall (cl : K.Clause) u k,
      Oracle cl = true ->
      cl (P.ctx_at u k).

  Axiom oracle_complete_generated :
    forall (cl : K.Clause),
      K.Generated cl ->
      Oracle cl = true.
End EXTERNAL_VALIDATION_ASSUMPTIONS.

Module Type VALIDATION_ASSUMPTIONS
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_FROM_PROVED_SIG P).
  Include EXTERNAL_VALIDATION_ASSUMPTIONS P K.
End VALIDATION_ASSUMPTIONS.

(*
  Any semantic oracle layer already provides the assumptions expected by the
  final correctness theorem.
*)
Module MakeExternalValidationAssumptionsFromOracleSem
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_FROM_PROVED_SIG P)
  (S : ORACLE_SEM_SIG P K)
  <: EXTERNAL_VALIDATION_ASSUMPTIONS P K.

  Definition Oracle : K.Clause -> bool := S.Oracle.

  Theorem oracle_sound_true :
    forall (cl : K.Clause) u k,
      Oracle cl = true ->
      cl (P.ctx_at u k).
  Proof.
    intros cl u k Hor.
    pose proof (S.Oracle_sound (cl := cl) Hor) as Hvalid.
    exact (S.clause_valid_pointwise (cl := cl) u k Hvalid).
  Qed.

  Theorem oracle_complete_generated :
    forall (cl : K.Clause),
      K.Generated cl ->
      Oracle cl = true.
  Proof.
    intros cl Hgen.
    exact (S.Oracle_complete (cl := cl) Hgen).
  Qed.
End MakeExternalValidationAssumptionsFromOracleSem.

Module MakeValidationAssumptionsFromOracleSem
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_FROM_PROVED_SIG P)
  (S : ORACLE_SEM_SIG P K)
  <: VALIDATION_ASSUMPTIONS P K.
  Include MakeExternalValidationAssumptionsFromOracleSem P K S.
End MakeValidationAssumptionsFromOracleSem.

(*
  Canonical instantiation path matching the implementation architecture:

  generated semantic clauses
    -> Hoare bundles attached to program transitions
    -> encoded external proof tasks
    -> checker answers
    -> semantic oracle assumptions for the final theorem.
*)
Module MakeExternalValidationAssumptionsFromTransitionTriples
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_FROM_PROVED_SIG P)
  (T : TRANSITION_TRIPLE_GEN_SIG P K)
  (X : EXTERNAL_TRIPLE_ENCODING_SIG P K T)
  (Ck : EXTERNAL_ENCODED_CHECKER_SIG P K T X)
  <: EXTERNAL_VALIDATION_ASSUMPTIONS P K.

  Module Sem :=
    TransitionTriplesBridge.MakeOracleSemFromTransitionTriples P K T X Ck.

  Include MakeExternalValidationAssumptionsFromOracleSem P K Sem.
End MakeExternalValidationAssumptionsFromTransitionTriples.

Module MakeValidationAssumptionsFromTransitionTriples
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_FROM_PROVED_SIG P)
  (T : TRANSITION_TRIPLE_GEN_SIG P K)
  (X : EXTERNAL_TRIPLE_ENCODING_SIG P K T)
  (Ck : EXTERNAL_ENCODED_CHECKER_SIG P K T X)
  <: VALIDATION_ASSUMPTIONS P K.
  Include MakeExternalValidationAssumptionsFromTransitionTriples P K T X Ck.
End MakeValidationAssumptionsFromTransitionTriples.
