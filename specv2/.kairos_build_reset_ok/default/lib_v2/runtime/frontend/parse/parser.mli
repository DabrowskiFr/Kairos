
(* The type of tokens. *)

type token = 
  | X
  | WITH
  | WHEN
  | W
  | TRUE
  | TREAL
  | TRANS
  | TO
  | TINT
  | THEN
  | TBOOL
  | STATES
  | STAR
  | SLASH
  | SKIP
  | SEMI
  | RPAREN
  | RETURNS
  | REQUIRES
  | RBRACK
  | RBRACE
  | R
  | PREK
  | PRE
  | PLUS
  | OR
  | NOT
  | NODE
  | NEQ
  | MINUS
  | MATCH
  | LT
  | LPAREN
  | LOCALS
  | LET
  | LE
  | LBRACK
  | LBRACE
  | INVARIANTS
  | INVARIANT
  | INT of (int)
  | INSTANCES
  | INSTANCE
  | INIT
  | IN
  | IMPL
  | IF
  | IDENT of (string)
  | GUARANTEE
  | GT
  | GE
  | G
  | FROM
  | FALSE
  | EQ
  | EOF
  | ENSURES
  | END
  | ELSE
  | CONTRACTS
  | COMMA
  | COLON
  | CALL
  | BAR
  | ASSUME
  | ASSIGN
  | ARROW
  | AND

(* This exception is raised by the monolithic API functions. *)

exception Error

(* The monolithic API. *)

val program: (Lexing.lexbuf -> token) -> Lexing.lexbuf -> (Ast.program)

module MenhirInterpreter : sig
  
  (* The incremental API. *)
  
  include MenhirLib.IncrementalEngine.INCREMENTAL_ENGINE
    with type token = token
  
  (* The indexed type of terminal symbols. *)
  
  type _ terminal = 
    | T_error : unit terminal
    | T_X : unit terminal
    | T_WITH : unit terminal
    | T_WHEN : unit terminal
    | T_W : unit terminal
    | T_TRUE : unit terminal
    | T_TREAL : unit terminal
    | T_TRANS : unit terminal
    | T_TO : unit terminal
    | T_TINT : unit terminal
    | T_THEN : unit terminal
    | T_TBOOL : unit terminal
    | T_STATES : unit terminal
    | T_STAR : unit terminal
    | T_SLASH : unit terminal
    | T_SKIP : unit terminal
    | T_SEMI : unit terminal
    | T_RPAREN : unit terminal
    | T_RETURNS : unit terminal
    | T_REQUIRES : unit terminal
    | T_RBRACK : unit terminal
    | T_RBRACE : unit terminal
    | T_R : unit terminal
    | T_PREK : unit terminal
    | T_PRE : unit terminal
    | T_PLUS : unit terminal
    | T_OR : unit terminal
    | T_NOT : unit terminal
    | T_NODE : unit terminal
    | T_NEQ : unit terminal
    | T_MINUS : unit terminal
    | T_MATCH : unit terminal
    | T_LT : unit terminal
    | T_LPAREN : unit terminal
    | T_LOCALS : unit terminal
    | T_LET : unit terminal
    | T_LE : unit terminal
    | T_LBRACK : unit terminal
    | T_LBRACE : unit terminal
    | T_INVARIANTS : unit terminal
    | T_INVARIANT : unit terminal
    | T_INT : (int) terminal
    | T_INSTANCES : unit terminal
    | T_INSTANCE : unit terminal
    | T_INIT : unit terminal
    | T_IN : unit terminal
    | T_IMPL : unit terminal
    | T_IF : unit terminal
    | T_IDENT : (string) terminal
    | T_GUARANTEE : unit terminal
    | T_GT : unit terminal
    | T_GE : unit terminal
    | T_G : unit terminal
    | T_FROM : unit terminal
    | T_FALSE : unit terminal
    | T_EQ : unit terminal
    | T_EOF : unit terminal
    | T_ENSURES : unit terminal
    | T_END : unit terminal
    | T_ELSE : unit terminal
    | T_CONTRACTS : unit terminal
    | T_COMMA : unit terminal
    | T_COLON : unit terminal
    | T_CALL : unit terminal
    | T_BAR : unit terminal
    | T_ASSUME : unit terminal
    | T_ASSIGN : unit terminal
    | T_ARROW : unit terminal
    | T_AND : unit terminal
  
  (* The indexed type of nonterminal symbols. *)
  
  type _ nonterminal = 
    | N_vdecls_opt : (Ast.vdecl list) nonterminal
    | N_vdecls : (Ast.vdecl list) nonterminal
    | N_vdecl_group : (Ast.vdecl list) nonterminal
    | N_ty : (Ast.ty) nonterminal
    | N_transitions : (Ast.transition list) nonterminal
    | N_transition_group : (Ast.transition list) nonterminal
    | N_trans_contracts_opt : (Ast.fo_o list * Ast.fo_o list) nonterminal
    | N_trans_contracts : (Ast.fo_o list * Ast.fo_o list) nonterminal
    | N_to_transitions : ((string * Ast.iexpr option * Ast.fo_o list * Ast.fo_o list * Ast.stmt list)
  list) nonterminal
    | N_to_transition : (string * Ast.iexpr option * Ast.fo_o list * Ast.fo_o list * Ast.stmt list) nonterminal
    | N_stmt_list_opt : (Ast.stmt list) nonterminal
    | N_stmt_list : (Ast.stmt list) nonterminal
    | N_stmt : (Ast.stmt) nonterminal
    | N_state_invariants_opt : (Ast.invariant_state_rel list) nonterminal
    | N_state_invariants : (Ast.invariant_state_rel list) nonterminal
    | N_state_invariant : (Ast.invariant_state_rel list) nonterminal
    | N_state_decls : (string list * string option) nonterminal
    | N_state_decl : (string * string option) nonterminal
    | N_relop : (Ast.relop) nonterminal
    | N_program : (Ast.program) nonterminal
    | N_params_opt : (Ast.vdecl list) nonterminal
    | N_params : (Ast.vdecl list) nonterminal
    | N_param : (Ast.vdecl) nonterminal
    | N_nodes : (Ast.program) nonterminal
    | N_node_contracts_block : (Ast.fo_ltl list * Ast.fo_ltl list) nonterminal
    | N_node_contracts : (Ast.fo_ltl list * Ast.fo_ltl list) nonterminal
    | N_node : (Ast.node) nonterminal
    | N_match_transitions : (Ast.transition list) nonterminal
    | N_match_transition : (Ast.transition) nonterminal
    | N_ltl_w : (Ast.fo_ltl) nonterminal
    | N_ltl_un : (Ast.fo_ltl) nonterminal
    | N_ltl_or : (Ast.fo_ltl) nonterminal
    | N_ltl_imp : (Ast.fo_ltl) nonterminal
    | N_ltl_atom : (Ast.fo_ltl) nonterminal
    | N_ltl_and : (Ast.fo_ltl) nonterminal
    | N_ltl : (Ast.fo_ltl) nonterminal
    | N_locals_opt : (Ast.vdecl list) nonterminal
    | N_invariant_formula_list : (Ast.fo list) nonterminal
    | N_invariant_entry : (Ast.invariant_state_rel list) nonterminal
    | N_invariant_entries : (Ast.invariant_state_rel list) nonterminal
    | N_instances_opt : ((string * string) list) nonterminal
    | N_instance_list : ((string * string) list) nonterminal
    | N_instance_decl : (string * string) nonterminal
    | N_iexpr_or : (Ast.iexpr) nonterminal
    | N_iexpr_not : (Ast.iexpr) nonterminal
    | N_iexpr_list_opt : (Ast.iexpr list) nonterminal
    | N_iexpr_list : (Ast.iexpr list) nonterminal
    | N_iexpr_atom : (Ast.iexpr) nonterminal
    | N_iexpr_and : (Ast.iexpr) nonterminal
    | N_iexpr : (Ast.iexpr) nonterminal
    | N_ident_list : (string list) nonterminal
    | N_id_list_opt : (string list) nonterminal
    | N_id_list : (string list) nonterminal
    | N_hexpr_list_opt : (Ast.hexpr list) nonterminal
    | N_hexpr_list : (Ast.hexpr list) nonterminal
    | N_hexpr : (Ast.hexpr) nonterminal
    | N_guard_opt : (Ast.iexpr option) nonterminal
    | N_fo_un : (Ast.fo) nonterminal
    | N_fo_or : (Ast.fo) nonterminal
    | N_fo_imp : (Ast.fo) nonterminal
    | N_fo_formula : (Ast.fo) nonterminal
    | N_fo_atom_noparen : (Ast.fo) nonterminal
    | N_fo_atom : (Ast.fo) nonterminal
    | N_fo_and : (Ast.fo) nonterminal
    | N_arith_unary : (Ast.iexpr) nonterminal
    | N_arith_mul : (Ast.iexpr) nonterminal
    | N_arith_atom : (Ast.iexpr) nonterminal
    | N_arith : (Ast.iexpr) nonterminal
    | N_alias_scope_start : (unit) nonterminal
    | N_alias_decls_opt : (unit) nonterminal
    | N_alias_decls : (unit) nonterminal
    | N_alias_decl : (unit) nonterminal
  
  (* The inspection API. *)
  
  include MenhirLib.IncrementalEngine.INSPECTION
    with type 'a lr1state := 'a lr1state
    with type production := production
    with type 'a terminal := 'a terminal
    with type 'a nonterminal := 'a nonterminal
    with type 'a env := 'a env
  
end

(* The entry point(s) to the incremental API. *)

module Incremental : sig
  
  val program: Lexing.position -> (Ast.program) MenhirInterpreter.checkpoint
  
end

(* The parse tables. *)

(* Warning: this submodule is undocumented. In the future,
   its type could change, or it could disappear altogether. *)

module Tables : MenhirLib.TableFormat.TABLES
  with type token = token
