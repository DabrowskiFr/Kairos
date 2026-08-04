(** Expansion and normalization of historical-expression aliases. *)

val is_scalar_ref_named : string -> Kr_lang_surface.Kr_lang_surface_syntax.indexed_ref -> bool
(** Test whether a reference is an unindexed occurrence of a name. *)

val ref_with_nat_params : Env.spec_context -> Kr_lang_surface.Kr_lang_surface_syntax.indexed_ref -> Kr_lang_surface.Kr_lang_surface_syntax.indexed_ref
(** Substitute natural-number parameters in a reference. *)

val scalar_nat_value : Env.spec_context -> Kr_lang_surface.Kr_lang_surface_syntax.indexed_ref -> int option
(** Resolve a scalar natural-number reference when possible. *)

val resolve_history_source_ref : Env.spec_context -> Kr_lang_surface.Kr_lang_surface_syntax.indexed_ref -> Kr_lang_surface.Kr_lang_surface_syntax.indexed_ref
(** Resolve natural-number and expression parameters in a history source. *)

val normalize_history_shift : int -> Kr_lang_core.Kr_lang_core_syntax.hexpr -> Kr_lang_core.Kr_lang_core_syntax.hexpr
(** Combine a history shift with nested history operators. *)

val expand_history_alias : Env.env -> string -> string -> Kr_lang_core.Kr_lang_core_syntax.hexpr
(** Expand a declared or implicit history alias. *)

val formula_arg_of_spec_arg : Env.spec_context -> Kr_lang_surface.Kr_lang_surface_syntax.spec_arg -> Kr_lang_surface.Kr_lang_surface_syntax.ltl
(** Extract an LTL argument from a specification argument. *)

val hexpr_arg_of_spec_arg : Env.spec_context -> Kr_lang_surface.Kr_lang_surface_syntax.spec_arg -> Kr_lang_surface.Kr_lang_surface_syntax.hexpr
(** Extract a historical-expression argument from a specification argument. *)

val nat_arg_of_spec_arg : Env.spec_context -> Kr_lang_surface.Kr_lang_surface_syntax.spec_arg -> int
(** Evaluate a natural-number specification argument. *)
