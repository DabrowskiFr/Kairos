type goal_info = Ide_lsp_types.goal_info

type outputs = Ide_lsp_types.outputs

type automata_outputs = Ide_lsp_types.automata_outputs

type why_outputs = Ide_lsp_types.why_outputs

type obligations_outputs = Ide_lsp_types.obligations_outputs

type config = Ide_lsp_types.config

type error = Ide_lsp_types.error =
  | Parse_error of string
  | Stage_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string

let error_to_string = Ide_lsp_types.error_to_string

let map_error_msg (s : string) : error = Stage_error s

let process_client : Ide_lsp_process_client.t option ref = ref None

let process_or_create () =
  match !process_client with
  | Some c -> c
  | None ->
      let c = Ide_lsp_process_client.create () in
      process_client := Some c;
      c

let did_open ~uri ~text =
  Ide_lsp_process_client.did_open (process_or_create ()) ~uri ~text |> Result.map_error map_error_msg

let did_change ~uri ~version ~text =
  Ide_lsp_process_client.did_change (process_or_create ()) ~uri ~version ~text
  |> Result.map_error map_error_msg

let did_save ~uri =
  Ide_lsp_process_client.did_save (process_or_create ()) ~uri |> Result.map_error map_error_msg

let did_close ~uri =
  Ide_lsp_process_client.did_close (process_or_create ()) ~uri |> Result.map_error map_error_msg

let instrumentation_pass ~generate_png ~input_file =
  Ide_lsp_process_client.instrumentation_pass (process_or_create ()) ~generate_png ~input_file
  |> Result.map_error map_error_msg

let why_pass ~prefix_fields ~input_file =
  Ide_lsp_process_client.why_pass (process_or_create ()) ~prefix_fields ~input_file
  |> Result.map_error map_error_msg

let obligations_pass ~prefix_fields ~prover ~input_file =
  Ide_lsp_process_client.obligations_pass (process_or_create ()) ~prefix_fields ~prover ~input_file
  |> Result.map_error map_error_msg

let eval_pass ~input_file ~trace_text ~with_state ~with_locals =
  Ide_lsp_process_client.eval_pass (process_or_create ()) ~input_file ~trace_text
    ~with_state ~with_locals
  |> Result.map_error map_error_msg

let run_with_callbacks cfg ~on_outputs_ready ~on_goals_ready ~on_goal_done =
  Ide_lsp_process_client.run_with_callbacks (process_or_create ()) cfg ~on_outputs_ready
    ~on_goals_ready ~on_goal_done
  |> Result.map_error map_error_msg

let dot_png_from_text dot =
  match Ide_lsp_process_client.dot_png_from_text (process_or_create ()) ~dot_text:dot with
  | Ok png -> png
  | Error _ -> None

let hover ~uri ~line ~character =
  Ide_lsp_process_client.hover (process_or_create ()) ~uri ~line ~character
  |> Result.map_error map_error_msg

let definition ~uri ~line ~character =
  Ide_lsp_process_client.definition (process_or_create ()) ~uri ~line ~character
  |> Result.map_error map_error_msg

let references ~uri ~line ~character =
  Ide_lsp_process_client.references (process_or_create ()) ~uri ~line ~character
  |> Result.map_error map_error_msg

let completion ~uri ~line ~character =
  Ide_lsp_process_client.completion (process_or_create ()) ~uri ~line ~character
  |> Result.map_error map_error_msg

let formatting ~uri =
  Ide_lsp_process_client.formatting (process_or_create ()) ~uri
  |> Result.map_error map_error_msg

let outline ~uri ~abstract_text =
  Ide_lsp_process_client.outline (process_or_create ()) ~uri ~abstract_text
  |> Result.map_error map_error_msg

let goals_tree_final ~goals ~vc_sources ~vc_text =
  Ide_lsp_process_client.goals_tree_final (process_or_create ()) ~goals ~vc_sources ~vc_text
  |> Result.map_error map_error_msg

let goals_tree_pending ~goal_names ~vc_ids ~vc_sources =
  Ide_lsp_process_client.goals_tree_pending (process_or_create ()) ~goal_names ~vc_ids
    ~vc_sources
  |> Result.map_error map_error_msg

let set_notification_handler _f = ()

let cancel_active () =
  ignore (Ide_lsp_process_client.cancel_active_request (process_or_create ()))
