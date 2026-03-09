open Ast

module Pass :
  Middle_end_pass.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.parsed
     and type stage_in = unit
     and type stage_out = Automata_pass_sig.stage
     and type info = Stage_info.automata_info = struct
  type ast_in = Stage_types.parsed
  type ast_out = Stage_types.parsed
  type stage_in = unit
  type stage_out = Automata_pass_sig.stage
  type info = Stage_info.automata_info

  let run_with_info (p : ast_in) () : ast_out * stage_out * info =
    Automata_default.run_with_info p ()

  let run (p : ast_in) () : ast_out * stage_out = Automata_default.run p ()
end
