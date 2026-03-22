(** Contract normalization on the abstract middle-end model. *)

val drop_user_transition_contracts :
  Normalized_program.node -> Normalized_program.node * int * int

val validate_user_pre_k_definedness :
  ?monitor_automaton:Spot_automaton.automaton -> Normalized_program.node -> unit

(** Run the abstract contract generation pipeline as:
    1. derive post-oriented state summaries
    2. inject the corresponding preconditions/coherency obligations *)
val generate_transition_contracts : Normalized_program.node -> Normalized_program.node
