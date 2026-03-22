(** Per-node automata builds reused across middle-end stages. *)

type t = (Ast.ident * Automata_generation.automata_build) list
