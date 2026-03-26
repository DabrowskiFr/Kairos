(** Shared helpers for bounded temporal history.

    This module groups the operations around:
    {ul
    {- [pre_k] expressions;}
    {- bounded history slots;}
    {- LTL shifting by a finite number of ticks.}} *)

(** Metadata attached to one history expression.

    - [expr] is the memorized expression.
    - [names] are the slot names, from most recent to oldest.
    - [vty] is the slot type. *)
type pre_k_info = { h : Ast.hexpr; expr : Ast.iexpr; names : string list; vty : Ast.ty }
[@@deriving yojson]

(** Result of normalizing an LTL formula with respect to the maximum [X]-depth
    it requires. *)
type ltl_norm = { ltl : Ast.ltl; k_guard : int option }

(** Maximum nesting depth of [X] operators in a formula. *)
val max_x_depth : Ast.ltl -> int

(** Embed a non-temporal first-order formula as an LTL formula. *)
val ltl_of_fo : Fo_formula.t -> Ast.ltl

(** Recover a non-temporal first-order formula from an LTL formula, failing on
    temporal formulas. *)
val fo_of_ltl : Ast.ltl -> Fo_formula.t

(** Decide whether an expression can safely stay in the current tick when
    history is shifted. *)
val is_const_iexpr : Ast.iexpr -> bool

(** Shift one history expression by [shift] ticks when representable. *)
val shift_hexpr_by : init_for_var:(Ast.ident -> Ast.iexpr) -> int -> Ast.hexpr -> Ast.hexpr option

(** Normalize an LTL formula and record the required [X]-depth in [k_guard]. *)
val normalize_ltl_for_k : init_for_var:(Ast.ident -> Ast.iexpr) -> Ast.ltl -> ltl_norm

(** Shift an entire LTL formula by [shift] ticks when representable. *)
val shift_ltl_by : init_for_var:(Ast.ident -> Ast.iexpr) -> int -> Ast.ltl -> Ast.ltl option
