open Ast

module Pass : Middle_end_pass.S
  with type ast_in = Stage_types.parsed
   and type ast_out = Stage_types.parsed
   and type stage_in = unit
   and type stage_out = Monitor_generation_pass_sig.stage
   and type info = Stage_info.monitor_generation_info = struct
  type ast_in = Stage_types.parsed
  type ast_out = Stage_types.parsed
  type stage_in = unit
  type stage_out = Monitor_generation_pass_sig.stage
  type info = Stage_info.monitor_generation_info

  let run_with_info (p:ast_in) () : ast_out * stage_out * info =
    Monitor_generation_default.run_with_info p ()

  let run (p:ast_in) () : ast_out * stage_out =
    Monitor_generation_default.run p ()
end
