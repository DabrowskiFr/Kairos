(** Lexer boundary used by [Kx_parse_api].

    It turns a UTF-8 Sedlex buffer into Menhir tokens and retains the last
    lexeme so parse failures can mention their immediate source context. Keyword
    tables and token-construction helpers remain private. *)

exception Lexing_error of string
(** Raised when the input cannot form a valid Kairos token. *)

val last_lexeme : unit -> string
(** Return the text of the most recently produced token. *)

val expected_tokens : (string * Kx_parse_parser.token) list
(** Representative tokens used to compute Menhir's acceptable-token list in a
    parse diagnostic. *)

val token : Sedlexing.lexbuf -> Kx_parse_parser.token
(** Read the next token from a UTF-8 source buffer. *)
