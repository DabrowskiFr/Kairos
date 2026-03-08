From SpecV2 Require Import ReactiveModel ConditionalSafety ExplicitProduct.

Set Implicit Arguments.

Section Clauses.
  Context (P : ReactiveProgram).
  Context (Spec : ConditionalSpec P).

  Definition Clause : Type := @TickCtx P Spec -> Prop.

  Variable node_inv : ProgState P -> @TickCtx P Spec -> Prop.

  Inductive coherence_kind : Type :=
  | CKNodeInvariant
  | CKAutomaton.

  Inductive clause_origin : Type :=
  | OriginSafety
  | OriginInit (k : coherence_kind)
  | OriginPropagation (k : coherence_kind).

  Definition ctx_matches_ps (ctx : @TickCtx P Spec) (ps : @ProductStep P Spec) : Prop :=
    cur_state ctx = ps_prog (pst_from ps)
    /\ cur_mem ctx = pst_mem ps
    /\ cur_input ctx = pst_input ps
    /\ cur_output ctx = pst_output ps
    /\ cur_trans ctx = pst_trans ps.

  Definition coherence_now
      (st : @ProductState P Spec)
      (ctx : @TickCtx P Spec)
      : Prop :=
    cur_state ctx = ps_prog st
    /\ cur_assume ctx = ps_assume st
    /\ cur_guarantee ctx = ps_guarantee st.

  Definition coherence_next
      (st : @ProductState P Spec)
      (ctx : @TickCtx P Spec)
      : Prop :=
    next_state ctx = ps_prog st
    /\ next_assume ctx = ps_assume st
    /\ next_guarantee ctx = ps_guarantee st.

  Definition no_bad_clause (ps : @ProductStep P Spec) : Clause :=
    fun ctx => ~ ctx_matches_ps ctx ps.

  Definition node_inv_clause (st : @ProductState P Spec) : Clause :=
    fun ctx => node_inv (ps_prog st) ctx.

  Definition automaton_coherence_clause (st : @ProductState P Spec) : Clause :=
    fun ctx => coherence_now st ctx.

  Inductive GeneratedClauseBy : clause_origin -> Clause -> Prop :=
  | GC_init_node_inv :
      GeneratedClauseBy (OriginInit CKNodeInvariant)
        (node_inv_clause {| ps_prog := init_state P;
                            ps_assume := q0 (assume_aut Spec);
                            ps_guarantee := q0 (guarantee_aut Spec) |})
  | GC_init_automaton :
      GeneratedClauseBy (OriginInit CKAutomaton)
        (automaton_coherence_clause {| ps_prog := init_state P;
                                       ps_assume := q0 (assume_aut Spec);
                                       ps_guarantee := q0 (guarantee_aut Spec) |})
  | GC_node_inv :
      forall ps,
        product_step_wf ps ->
        GeneratedClauseBy (OriginPropagation CKNodeInvariant)
          (node_inv_clause (pst_target ps))
  | GC_automaton :
      forall ps,
        product_step_wf ps ->
        GeneratedClauseBy (OriginPropagation CKAutomaton)
          (automaton_coherence_clause (pst_target ps))
  | GC_no_bad :
      forall ps,
        product_step_wf ps ->
        product_step_is_bad_target ps ->
        GeneratedClauseBy OriginSafety (no_bad_clause ps).

  Definition GeneratedClause (cl : Clause) : Prop :=
    exists o, GeneratedClauseBy o cl.
End Clauses.
