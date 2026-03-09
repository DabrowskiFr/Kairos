include Lsp_protocol

type request_id = int

type capabilities = {
  supports_incremental_prove : bool;
  supports_automata : bool;
  supports_outline : bool;
  supports_diagnostics : bool;
}

type init_params = { client_name : string; client_version : string option }

type init_result = { server_name : string; server_version : string; capabilities : capabilities }

type error =
  | Parse_error of string
  | Stage_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string

let error_to_string = function
  | Parse_error s -> "Parse error: " ^ s
  | Stage_error s -> "Stage error: " ^ s
  | Why3_error s -> "Why3 error: " ^ s
  | Prove_error s -> "Prove error: " ^ s
  | Io_error s -> "I/O error: " ^ s

type notification =
  | Publish_diagnostic of { stage : string; message : string }
  | Progress of { request_id : request_id; phase : string; message : string option }
  | Goals_ready of { request_id : request_id; names : string list; vc_ids : int list }
  | Goal_done of {
      request_id : request_id;
      idx : int;
      goal : string;
      status : string;
      time_s : float;
      dump_path : string option;
      source : string;
      vcid : string option;
    }
  | Outputs_ready of { request_id : request_id; outputs : outputs }

type request =
  | Initialize of init_params
  | Shutdown
  | Did_open of { uri : string; text : string }
  | Did_change of { uri : string; version : int; text : string }
  | Did_save of { uri : string }
  | Instrumentation_pass of { generate_png : bool; input_file : string }
  | Obc_pass of { input_file : string }
  | Why_pass of { prefix_fields : bool; input_file : string }
  | Obligations_pass of { prefix_fields : bool; prover : string; input_file : string }
  | Eval_pass of {
      input_file : string;
      trace_text : string;
      with_state : bool;
      with_locals : bool;
    }
  | Dot_png_from_text of string
  | Run_with_callbacks of config

type response =
  | Initialized of init_result
  | Acknowledged
  | Instrumentation_out of automata_outputs
  | Obc_out of obc_outputs
  | Why_out of why_outputs
  | Obligations_out of obligations_outputs
  | Eval_out of string
  | Dot_png_out of string option
  | Run_out of outputs
