(** Signature for the automaton stage implementation. *)

type stage = (Ast.ident * Monitor_generation.monitor_generation_automaton) list

module type S = sig
  include Middle_end_pass.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.parsed
     and type stage_in = unit
     and type stage_out = stage
     and type info = Stage_info.automaton_info
end
