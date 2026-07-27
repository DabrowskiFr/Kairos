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

(** Why3 expression compiler.

    This module owns the Ptree constructors used for expressions, type and
    operator mappings, environment access, stable term keys, and compilation
    of immediate and historical Kairos expressions. *)

module StringSet : Set.S with type elt = string

type used_inputs = StringSet.t

(** Compilation context for a single node.

    - [rec_name]: name of the WhyML mutable record holding state variables
      (always ["vars"] in practice).
    - [rec_vars]: names of variables stored in the record (state, locals,
      outputs). Used to route accesses as [vars.x] vs plain [x]. *)
type env = {
  rec_name : string;
  rec_vars : string list;
  used_inputs : used_inputs ref option;
}

(** [collect_used_inputs env compile] runs one delimited translation and
    returns the input parameters read while constructing its Why3 tree. *)
val collect_used_inputs : env -> (env -> 'a) -> 'a * used_inputs

(** Records a generated access to an input parameter. *)
val note_input : env -> string -> unit

(** Dummy source position attached to all generated Why3 AST nodes. *)
val loc : Why3.Loc.position

(** Builds a Why3 identifier from a string. *)
val ident : string -> Why3.Ptree.ident

(** Builds an unqualified qualid from a string. *)
val qid1 : string -> Why3.Ptree.qualid

(** Wraps an expression descriptor into a Why3 expression node. *)
val mk_expr : Why3.Ptree.expr_desc -> Why3.Ptree.expr

(** Wraps a term descriptor into a Why3 term node. *)
val mk_term : Why3.Ptree.term_desc -> Why3.Ptree.term

(** [term_eq a b] builds the term [a = b]. *)
val term_eq : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term

(** [term_implies a b] builds the term [a -> b]. *)
val term_implies : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term

(** Translates a Kairos type into the corresponding Why3 type. *)
val default_pty : Core_syntax.ty -> Why3.Ptree.pty

(** [field env name] builds the expression [vars.name]. *)
val field : env -> Core_syntax.ident -> Why3.Ptree.expr

(** Tests whether a variable name is stored in the record. *)
val is_rec_var : env -> Core_syntax.ident -> bool

(** [term_of_var env name] builds the term for variable [name]. *)
val term_of_var : env -> Core_syntax.ident -> Why3.Ptree.term

(** Removes structurally duplicate terms while preserving their order. *)
val uniq_terms : Why3.Ptree.term list -> Why3.Ptree.term list

(** [compile_expr env e] compiles an immediate Kairos expression to a Why3
    expression. Local and output variables are accessed through the [vars]
    record; inputs are direct parameters. *)
val compile_expr : env -> Core_syntax.expr -> Why3.Ptree.expr

(** [compile_term env e] compiles an immediate Kairos expression to a Why3
    term (logical form, used inside contracts). *)
val compile_term : env -> Core_syntax.expr -> Why3.Ptree.term

(** [compile_hexpr env f] compiles a canonical first-order formula from the IR
    to a Why3 term. *)
val compile_hexpr :
  env -> Core_syntax.history_free Core_syntax.hexpr -> Why3.Ptree.term
