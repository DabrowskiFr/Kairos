Set Implicit Arguments.

Module Type FO_LOGIC_SIG.
  Parameter InputVal OutputVal : Type.
  Parameter StepCtx : Type.
  Parameter ctx_at : (nat -> InputVal) -> nat -> StepCtx.

  Parameter FO : Type.
  Parameter eval_fo : StepCtx -> FO -> Prop.
  Parameter shift_fo : nat -> FO -> FO.
End FO_LOGIC_SIG.
