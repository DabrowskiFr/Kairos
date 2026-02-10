(** Constructors and utility helpers for the AST. *)

val mk_iexpr : ?loc:Ast.loc -> Ast.iexpr_desc -> Ast.iexpr
val iexpr_desc : Ast.iexpr -> Ast.iexpr_desc
val with_iexpr_desc : Ast.iexpr -> Ast.iexpr_desc -> Ast.iexpr
val mk_var : Ast.ident -> Ast.iexpr
val mk_int : int -> Ast.iexpr
val mk_bool : bool -> Ast.iexpr
val as_var : Ast.iexpr -> Ast.ident option

val mk_stmt : ?loc:Ast.loc -> Ast.stmt_desc -> Ast.stmt
val stmt_desc : Ast.stmt -> Ast.stmt_desc
val with_stmt_desc : Ast.stmt -> Ast.stmt_desc -> Ast.stmt

val empty_node_attrs : Ast.node_attrs
val empty_transition_attrs : Ast.transition_attrs
val ensure_program_uids : Ast.program -> Ast.program

val mk_transition :
  src:Ast.ident ->
  dst:Ast.ident ->
  guard:Ast.iexpr option ->
  requires:Ast.fo_o list ->
  ensures:Ast.fo_o list ->
  body:Ast.stmt list ->
  Ast.transition

val mk_node :
  nname:Ast.ident ->
  inputs:Ast.vdecl list ->
  outputs:Ast.vdecl list ->
  assumes:Ast.fo_ltl list ->
  guarantees:Ast.fo_ltl list ->
  instances:(Ast.ident * Ast.ident) list ->
  locals:Ast.vdecl list ->
  states:Ast.ident list ->
  init_state:Ast.ident ->
  trans:Ast.transition list ->
  Ast.node
