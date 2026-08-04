(** Backend-independent canonical keys for formulas. *)

type key

val key :
  ?normalize:('phase Kr_domain_core_syntax.hexpr -> 'phase Kr_domain_core_syntax.hexpr) ->
  'phase Kr_domain_core_syntax.hexpr ->
  key

val negated_key :
  ?normalize:('phase Kr_domain_core_syntax.hexpr -> 'phase Kr_domain_core_syntax.hexpr) ->
  'phase Kr_domain_core_syntax.hexpr ->
  key
(** Canonical key of the explicit logical negation of a formula. *)
