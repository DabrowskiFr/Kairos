(** Source-file level representation combining explicit imports and the parsed
    node program. *)

(** One syntactic import declaration as it appears in the source file. *)
type import_decl = {
  import_path : string;
  import_loc : Ast.loc option;
}

(** Parsed source file, before imports are resolved or expanded. *)
type t = {
  imports : import_decl list;
  nodes : Ast.program;
}

(** Empty source file value used by tests and default initialization paths. *)
val empty : t

(** Paths referenced by the explicit imports of the file, in source order. *)
val imported_paths : t -> string list
