(** Conversions from lowered first-order formulas to Core expressions and LTL. *)

val ltl_of_fo : Kr_lang_core.Kr_lang_core_syntax.hexpr -> Kr_lang_core.Kr_lang_core_syntax.ltl
(** Convert a boolean historical expression to an LTL formula. *)

val expr_of_fo : Kr_lang_core.Kr_lang_core_syntax.hexpr -> Kr_lang_core.Kr_lang_core_syntax.expr
(** Convert an executable historical expression to a Core expression. *)

val core_ltl_and : Kr_lang_core.Kr_lang_core_syntax.ltl list -> Kr_lang_core.Kr_lang_core_syntax.ltl
(** Build a conjunction, using [true] for an empty list. *)

val core_ltl_or : Kr_lang_core.Kr_lang_core_syntax.ltl list -> Kr_lang_core.Kr_lang_core_syntax.ltl
(** Build a disjunction, using [false] for an empty list. *)

val core_hexpr_and : Kr_lang_core.Kr_lang_core_syntax.hexpr list -> Kr_lang_core.Kr_lang_core_syntax.hexpr
(** Build a historical-expression conjunction. *)

val core_hexpr_or : Kr_lang_core.Kr_lang_core_syntax.hexpr list -> Kr_lang_core.Kr_lang_core_syntax.hexpr
(** Build a historical-expression disjunction. *)
