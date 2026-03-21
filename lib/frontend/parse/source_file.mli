(** Source-file level representation combining explicit imports and the parsed
    node program. *)

type import_decl = {
  import_path : string;
  import_loc : Ast.loc option;
}

type t = {
  imports : import_decl list;
  nodes : Ast.program;
}

val empty : t
val imported_paths : t -> string list
