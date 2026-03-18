type import_decl = {
  import_path : string;
  import_loc : Ast.loc option;
}

type t = {
  imports : import_decl list;
  nodes : Ast.program;
}

let empty : t = { imports = []; nodes = [] }
let imported_paths (source : t) : string list = List.map (fun decl -> decl.import_path) source.imports
