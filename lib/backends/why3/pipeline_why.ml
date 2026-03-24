(** Why/VC/SMT export passes extracted from the v2 pipeline implementation. *)

let join_blocks ~sep blocks =
  let b = Buffer.create 4096 in
  List.iteri
    (fun i s ->
      if i > 0 then Buffer.add_string b sep;
      Buffer.add_string b s)
    blocks;
  Buffer.contents b

let compile_why_text ~with_why_translation_mode ~prefix_fields ~why_translation_mode
    ~(asts : Pipeline_api_types.ast_stages) ~(infos : Pipeline_api_types.stage_infos) =
  let instrumentation_info =
    Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
  in
  let kernel_ir_map =
    List.map (fun (ir : Proof_kernel_ir.node_ir) -> (ir.reactive_program.node_name, ir))
      instrumentation_info.kernel_ir_nodes
  in
  let program_summaries = instrumentation_info.exported_node_summaries in
  with_why_translation_mode why_translation_mode (fun () ->
      let why_ast =
        Emit.compile_program_ast_from_summaries ~prefix_fields ~kernel_ir_map
          ~external_summaries:asts.imported_summaries program_summaries
      in
      Emit.emit_program_ast why_ast)

let why_pass ~build_ast_with_info ~stage_meta ~with_why_translation_mode ~prefix_fields
    ~why_translation_mode ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let why_text =
        compile_why_text ~with_why_translation_mode ~prefix_fields ~why_translation_mode
          ~asts ~infos
      in
      Ok { Pipeline_api_types.why_text = why_text; stage_meta = stage_meta infos }

let obligations_pass ~build_ast_with_info ~with_why_translation_mode ~prefix_fields
    ~why_translation_mode ~prover ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let why_text =
        compile_why_text ~with_why_translation_mode ~prefix_fields ~why_translation_mode
          ~asts ~infos
      in
      let vc_text =
        join_blocks ~sep:"\n(* ---- goal ---- *)\n"
          (Why_contract_prove.dump_why3_tasks_with_attrs ~text:why_text)
      in
      let smt_text =
        join_blocks ~sep:"\n; ---- goal ----\n"
          (Why_contract_prove.dump_smt2_tasks ~prover ~text:why_text)
      in
      Ok { Pipeline_api_types.vc_text = vc_text; smt_text }
