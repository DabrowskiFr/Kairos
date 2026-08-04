(** Backend-independent canonical keys for formulas. *)

type key

val key :
  ?normalize:('phase Core_syntax.hexpr -> 'phase Core_syntax.hexpr) ->
  'phase Core_syntax.hexpr ->
  key

val negated_key :
  ?normalize:('phase Core_syntax.hexpr -> 'phase Core_syntax.hexpr) ->
  'phase Core_syntax.hexpr ->
  key
(** Canonical key of the explicit logical negation of a formula. *)
