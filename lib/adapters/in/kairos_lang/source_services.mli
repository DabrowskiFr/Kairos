(** Source-oriented services that do not expose frontend ASTs. Editor services
    analyze source text directly because an LSP buffer may not be saved, while
    CLI dump services read an input file. *)

type source_diagnostic = {
  line : int; (** Zero-based line. *)
  column : int; (** Zero-based column, in Unicode code points. *)
  line_end : int; (** Zero-based end line. *)
  column_end : int; (** Zero-based end column, in Unicode code points. *)
  severity : int; (** LSP-compatible severity. *)
  source : string; (** Frontend stage that emitted the diagnostic. *)
  message : string; (** Human-readable explanation. *)
}
(** A parsing or elaboration problem located in the source. The LSP converts it
    into a diagnostic displayed by the editor. *)

type semantic_symbols = {
  all : string list; (** Every discovered symbol. *)
  nodes : string list; (** Node names. *)
  states : string list; (** Control-state names. *)
  variables : string list; (** Program-variable names. *)
}
(** Names declared by the program, grouped by kind. The LSP uses them notably
    to provide completion. *)

val diagnostics :
  filename:string ->
  text:string ->
  source_diagnostic list
(** Parse and elaborate source text into editor diagnostics. *)

val semantic_symbols :
  filename:string ->
  text:string ->
  semantic_symbols option
(** Extract symbols when the source can be elaborated. *)

val surface_dump :
  input_file:string ->
  (string, Frontend.error) result
(** Render the parsed surface syntax as JSON. *)

val elaborated_dump :
  input_file:string ->
  (string, Frontend.error) result
(** Render the elaborated syntax as JSON. *)
