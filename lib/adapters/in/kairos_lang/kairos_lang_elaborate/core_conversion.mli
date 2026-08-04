(** Conversions from lowered first-order formulas to Core expressions and LTL. *)

val ltl_of_fo : Core.Syntax.hexpr -> Core.Syntax.ltl
(** Convert a boolean historical expression to an LTL formula. *)

val expr_of_fo : Core.Syntax.hexpr -> Core.Syntax.expr
(** Convert an executable historical expression to a Core expression. *)

val core_ltl_and : Core.Syntax.ltl list -> Core.Syntax.ltl
(** Build a conjunction, using [true] for an empty list. *)

val core_ltl_or : Core.Syntax.ltl list -> Core.Syntax.ltl
(** Build a disjunction, using [false] for an empty list. *)

val core_hexpr_and : Core.Syntax.hexpr list -> Core.Syntax.hexpr
(** Build a historical-expression conjunction. *)

val core_hexpr_or : Core.Syntax.hexpr list -> Core.Syntax.hexpr
(** Build a historical-expression disjunction. *)
