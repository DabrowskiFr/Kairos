Set Implicit Arguments.

Module Type LTL_PREDICATE_SIG.
  Parameter Obs : Type.
  Definition stream (A : Type) : Type := nat -> A.

  (* Abstract LTL formulas, represented extensionally as predicates on traces. *)
  Definition Formula : Type := stream Obs -> Prop.

  Definition sat (phi : Formula) (w : stream Obs) : Prop := phi w.
End LTL_PREDICATE_SIG.
