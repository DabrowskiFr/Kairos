(** Constructors and utility helpers for the AST.

   These helpers centralize defaults (locations) and make parser/transform code more compact. *)

(** Build an immediate expression with an optional source location. *)
val mk_iexpr : ?loc:Ast.loc -> Ast.iexpr_desc -> Ast.iexpr

(** Extract the underlying descriptor from an immediate expression. *)
val iexpr_desc : Ast.iexpr -> Ast.iexpr_desc

(** Replace the descriptor while preserving the source location. *)
val with_iexpr_desc : Ast.iexpr -> Ast.iexpr_desc -> Ast.iexpr

(** Convenience constructor for a variable expression. *)
val mk_var : Ast.ident -> Ast.iexpr

(** Convenience constructor for an integer literal. *)
val mk_int : int -> Ast.iexpr

(** Convenience constructor for a boolean literal. *)
val mk_bool : bool -> Ast.iexpr

(** Return the identifier when the expression is a variable. *)
val as_var : Ast.iexpr -> Ast.ident option

(** Build a statement with an optional source location. *)
val mk_stmt : ?loc:Ast.loc -> Ast.stmt_desc -> Ast.stmt

(** Extract the underlying descriptor from a statement. *)
val stmt_desc : Ast.stmt -> Ast.stmt_desc

(** Replace the descriptor while preserving the source location. *)
val with_stmt_desc : Ast.stmt -> Ast.stmt_desc -> Ast.stmt

(** Build a source transition. *)
val mk_transition :
  src:Ast.ident ->
  dst:Ast.ident ->
  guard:Ast.iexpr option ->
  body:Ast.stmt list ->
  Ast.transition

(** Build a source node. *)
val mk_node :
  nname:Ast.ident ->
  inputs:Ast.vdecl list ->
  outputs:Ast.vdecl list ->
  assumes:Ast.ltl list ->
  guarantees:Ast.ltl list ->
  instances:(Ast.ident * Ast.ident) list ->
  locals:Ast.vdecl list ->
  states:Ast.ident list ->
  init_state:Ast.ident ->
  trans:Ast.transition list ->
  Ast.node
