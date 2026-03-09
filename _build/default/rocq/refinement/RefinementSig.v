Set Implicit Arguments.

Module Type REFINEMENT_SIG.
  Parameter AbsCtx ConcrCtx : Type.
  Parameter AbsFO ConcrFO : Type.

  Parameter refines_ctx : ConcrCtx -> AbsCtx -> Prop.
  Parameter refines_fo : ConcrFO -> AbsFO -> Prop.

  Parameter eval_abs : AbsCtx -> AbsFO -> Prop.
  Parameter eval_concr : ConcrCtx -> ConcrFO -> Prop.

  Axiom refinement_sound :
    forall cctx actx cfo afo,
      refines_ctx cctx actx ->
      refines_fo cfo afo ->
      eval_concr cctx cfo ->
      eval_abs actx afo.
End REFINEMENT_SIG.
