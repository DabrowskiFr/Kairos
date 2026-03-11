(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(* {1 Environment Types} Internal environment used by Why3 emission and normalization helpers. *)

(* Metadata describing a single pre‑k expression and its generated names. *)
type pre_k_info = { h : Ast.hexpr; expr : Ast.iexpr; names : string list; vty : Ast.ty }
[@@deriving yojson]

(* Accumulated environment for a node during emission. *)
type env = {
  rec_name : string;
  rec_vars : string list;
  var_map : (Ast.ident * Ast.ident) list;
  links : (Ast.hexpr * Ast.ident) list;
  pre_k : (Ast.hexpr * pre_k_info) list;
  inst_map : (Ast.ident * Ast.ident) list;
  inputs : Ast.ident list;
}

(* {1 Identifiers And Names} *)
(* Why3 location placeholder (used when no precise loc is available). *)
val loc : Why3.Loc.position

(* Build a Why3 identifier. *)
val ident : string -> Why3.Ptree.ident

(* Build a Why3 infix identifier. *)
val infix_ident : string -> Why3.Ptree.ident

(* Build a qualified id from a single name. *)
val qid1 : string -> Why3.Ptree.qualid

(* Extend a qualified id with a dotted suffix. *)
val qdot : Why3.Ptree.qualid -> string -> Why3.Ptree.qualid

(* Canonical module name for a node. *)
val module_name_of_node : Ast.ident -> string

(* Field prefix for a node instance. *)
val prefix_for_node : Ast.ident -> string

(* Name of the pre-input variable. *)
val pre_input_name : Ast.ident -> string

(* Name of the old pre-input variable. *)
val pre_input_old_name : Ast.ident -> string

(* {1 Why3 Constructors}
    Small builders for Why3 parse tree nodes. *)
(* Build expr. *)
val mk_expr : Why3.Ptree.expr_desc -> Why3.Ptree.expr

(* Build term. *)
val mk_term : Why3.Ptree.term_desc -> Why3.Ptree.term

(* Compute term eq. *)
val term_eq : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term

(* Compute term neq. *)
val term_neq : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term

(* Compute term implies. *)
val term_implies : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term

(* Compute term old. *)
val term_old : Why3.Ptree.term -> Why3.Ptree.term

(* Compute apply expr. *)
val apply_expr : Why3.Ptree.expr -> Why3.Ptree.expr list -> Why3.Ptree.expr

(* Compute default pty. *)
val default_pty : Ast.ty -> Why3.Ptree.pty

(* Render a binary operator as a string. *)
val binop_id : Ast.binop -> string

(* {1 Environment Lookups} *)
(* Compute rec var name. *)
val rec_var_name : env -> Ast.ident -> Ast.ident

(* Compute field. *)
val field : env -> Ast.ident -> Why3.Ptree.expr

(* Predicate for rec var. *)
val is_rec_var : env -> Ast.ident -> bool

(* Compute term var. *)
val term_var : env -> Ast.ident -> Why3.Ptree.term_desc

(* Compute find link. *)
val find_link : env -> Ast.hexpr -> Ast.ident option

(* Compute find pre k. *)
val find_pre_k : env -> Ast.hexpr -> pre_k_info option

(* {1 Pretty Printing} *)
(* Render qid as a string. *)
val string_of_qid : Why3.Ptree.qualid -> string

(* Render const as a string. *)
val string_of_const : Why3.Constant.constant -> string

(* Render relop as a string. *)
val string_of_relop : Ast.relop -> string

type ltl_norm = { ltl : Ast.fo_ltl; k_guard : int option }

(* {1 Logical Helpers} *)
(* Compute max x depth. *)
val max_x_depth : Ast.fo_ltl -> int

(* Lift a FO formula to LTL. *)
val ltl_of_fo : Ast.fo -> Ast.fo_ltl

(* Project an LTL formula to FO when possible. *)
val fo_of_ltl : Ast.fo_ltl -> Ast.fo

(* Predicate for const iexpr. *)
val is_const_iexpr : Ast.iexpr -> bool

(* {1 Shifts And Normalization} *)
(* Shift hexpr by. *)
val shift_hexpr_by : init_for_var:(Ast.ident -> Ast.iexpr) -> int -> Ast.hexpr -> Ast.hexpr option

(* Normalize ltl for k. *)
val normalize_ltl_for_k : init_for_var:(Ast.ident -> Ast.iexpr) -> Ast.fo_ltl -> ltl_norm

(* Shift ltl by. *)
val shift_ltl_by : init_for_var:(Ast.ident -> Ast.iexpr) -> int -> Ast.fo_ltl -> Ast.fo_ltl option

(* {1 String Rendering} *)
(* Render iexpr as a string. *)
val string_of_iexpr : ?ctx:int -> Ast.iexpr -> string

(* Render hexpr as a string. *)
val string_of_hexpr : Ast.hexpr -> string

(* Render fo as a string. *)
val string_of_fo : ?ctx:int -> Ast.fo -> string

(* Render ltl as a string. *)
val string_of_ltl : ?ctx:int -> Ast.fo_ltl -> string

(* Normalize infix. *)
val normalize_infix : string -> string

(* Render term as a string. *)
val string_of_term : Why3.Ptree.term -> string

(* Remove duplicates while preserving order. *)
val uniq_terms : Why3.Ptree.term list -> Why3.Ptree.term list

(* Build a term from var. *)
val term_of_var : env -> Ast.ident -> Why3.Ptree.term

(* Render a relational operator as a string. *)
val relop_id : Ast.relop -> string

(* Build a term from instance var. *)
val term_of_instance_var : env -> Ast.ident -> Ast.ident -> Ast.ident -> Why3.Ptree.term

(* Build an expression from instance var. *)
val expr_of_instance_var : env -> Ast.ident -> Ast.ident -> Ast.ident -> Why3.Ptree.expr
