(** Backend-independent canonical keys and physical interning for formulas. *)

type key
type 'phase pool

val key :
  ?normalize:('phase Core_syntax.hexpr -> 'phase Core_syntax.hexpr) ->
  'phase Core_syntax.hexpr ->
  key

val negated_key :
  ?normalize:('phase Core_syntax.hexpr -> 'phase Core_syntax.hexpr) ->
  'phase Core_syntax.hexpr ->
  key
(** Canonical key of the explicit logical negation of a formula. *)

val create_pool : ?size:int -> unit -> 'phase pool

val intern :
  ?normalize:('phase Core_syntax.hexpr -> 'phase Core_syntax.hexpr) ->
  'phase pool ->
  'phase Core_syntax.hexpr ->
  'phase Core_syntax.hexpr
