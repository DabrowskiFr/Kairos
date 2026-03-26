(** Small helpers to decode JSON-RPC/LSP request payloads. *)

val position_from_params : Yojson.Safe.t -> (int * int) option

val get_param_string : Yojson.Safe.t -> string -> string option
val get_param_bool : Yojson.Safe.t -> string -> bool -> bool
val get_param_int : Yojson.Safe.t -> string -> int -> int
val get_param_list : Yojson.Safe.t -> string -> Yojson.Safe.t list option

val get_text_document_uri : Yojson.Safe.t -> string option
val get_did_open_text : Yojson.Safe.t -> string option
val get_did_change_text : Yojson.Safe.t -> string option
val client_supports_work_done_progress : Yojson.Safe.t -> bool

val map_outputs : Pipeline_types.outputs -> Lsp_protocol.outputs
val map_automata : Pipeline_types.automata_outputs -> Lsp_protocol.automata_outputs
val map_why : Pipeline_types.why_outputs -> Lsp_protocol.why_outputs
val map_oblig : Pipeline_types.obligations_outputs -> Lsp_protocol.obligations_outputs
