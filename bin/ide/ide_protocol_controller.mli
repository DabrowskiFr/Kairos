type t

val create : add_history:(string -> unit) -> t
val cancel_active : t -> unit
val did_open : t -> uri:string -> text:string -> unit
val did_change : t -> uri:string -> version:int -> text:string -> unit
val did_save : t -> uri:string -> unit
val did_close : t -> uri:string -> unit
val hover : t -> uri:string -> line:int -> character:int -> string option
val definition : t -> uri:string -> line:int -> character:int -> (int * int) option
val references : t -> uri:string -> line:int -> character:int -> (int * int) list
val completion : t -> uri:string -> line:int -> character:int -> string list
val formatting : t -> uri:string -> string option
val outline : t -> uri:string -> abstract_text:string -> Ide_lsp_types.outline_payload option

val goals_tree_final :
  t ->
  goals:Ide_lsp_types.goal_info list ->
  vc_sources:(int * string) list ->
  vc_text:string ->
  Ide_lsp_types.goal_tree_node list

val goals_tree_pending :
  t ->
  goal_names:string list ->
  vc_ids:int list ->
  vc_sources:(int * string) list ->
  Ide_lsp_types.goal_tree_node list
