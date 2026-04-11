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

(** Compilation environment, Why3 primitives, and Kairos expression compiler.

    Defines the [env] type shared by all Why3 backend modules, the low-level
    Why3 [Ptree] construction helpers, and the functions that translate Kairos
    expressions and formulas into Why3 terms and expressions. *)

(** Compilation context for a single node.

    - [rec_name]: name of the WhyML mutable record holding state variables
      (always ["vars"] in practice).
    - [rec_vars]: names of variables stored in the record (state, locals,
      outputs). Used to route accesses as [vars.x] vs plain [x].
    - [links]: mapping from historical expressions to invariant predicate
      identifiers, used to avoid re-expanding past expressions in contracts. *)
type env = {
  rec_name : string;
  rec_vars : string list;
  links : (Core_syntax.hexpr * Core_syntax.ident) list;
}

(** Dummy source position attached to all generated Why3 AST nodes. *)
val loc : Why3.Loc.position

(** Builds a Why3 identifier from a string. *)
val ident : string -> Why3.Ptree.ident

(** Builds a Why3 infix operator identifier (e.g. ["+"], ["="]). *)
val infix_ident : string -> Why3.Ptree.ident

(** Builds an unqualified qualid from a string. *)
val qid1 : string -> Why3.Ptree.qualid

(** [qdot q s] builds the qualified identifier [q.s]. *)
val qdot : Why3.Ptree.qualid -> string -> Why3.Ptree.qualid

(** Wraps an expression descriptor into a Why3 expression node. *)
val mk_expr : Why3.Ptree.expr_desc -> Why3.Ptree.expr

(** Wraps a term descriptor into a Why3 term node. *)
val mk_term : Why3.Ptree.term_desc -> Why3.Ptree.term

(** [term_eq a b] builds the term [a = b]. *)
val term_eq : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term

(** [term_neq a b] builds the term [a <> b]. *)
val term_neq : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term

(** Builds a binary Boolean connective in Why3. *)
val term_bool_binop : Why3.Dterm.dbinop -> Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term

(** [term_implies a b] builds the term [a -> b]. *)
val term_implies : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term

(** [term_old t] wraps [t] with the WhyML [old] keyword. *)
val term_old : Why3.Ptree.term -> Why3.Ptree.term

(** [apply_expr fn args] builds the curried application [fn arg1 arg2 ...]. *)
val apply_expr : Why3.Ptree.expr -> Why3.Ptree.expr list -> Why3.Ptree.expr

(** Translates a Kairos type into the corresponding Why3 type. *)
val default_pty : Core_syntax.ty -> Why3.Ptree.pty

(** Returns the textual representation of a Kairos binary operator. *)
val binop_id : Core_syntax.binop -> string

(** Returns the textual representation of a Kairos relational operator. *)
val relop_id : Core_syntax.relop -> string

(** [field env name] builds the expression [vars.name]. *)
val field : env -> Core_syntax.ident -> Why3.Ptree.expr

(** Tests whether a variable name is stored in the record. *)
val is_rec_var : env -> Core_syntax.ident -> bool

(** [term_var env x] builds the term descriptor for [x]:
    [vars.x] if [x] is a record variable, plain [x] otherwise. *)
val term_var : env -> Core_syntax.ident -> Why3.Ptree.term_desc

(** Looks up the invariant predicate linked to a historical expression. *)
val find_link : env -> Core_syntax.hexpr -> Core_syntax.ident option

(** [term_of_var env name] builds the term for variable [name]. *)
val term_of_var : env -> Core_syntax.ident -> Why3.Ptree.term

(** Serialises a qualid to a string. *)
val string_of_qid : Why3.Ptree.qualid -> string

(** Serialises a Why3 term to a string (used for deduplication). *)
val string_of_term : Why3.Ptree.term -> string

(** Removes duplicate terms from a list using their textual representation. *)
val uniq_terms : Why3.Ptree.term list -> Why3.Ptree.term list

(** [compile_expr env e] compiles an immediate Kairos expression to a Why3
    expression. Local and output variables are accessed through the [vars]
    record; inputs are direct parameters. *)
val compile_expr : env -> Core_syntax.expr -> Why3.Ptree.expr

(** [compile_term env e] compiles an immediate Kairos expression to a Why3
    term (logical form, used inside contracts). *)
val compile_term : env -> Core_syntax.expr -> Why3.Ptree.term

(** [term_of_outputs env outputs] builds the tuple term representing the node
    outputs in a postcondition. Returns [None] when the list is empty. *)
val term_of_outputs : env -> Core_syntax.vdecl list -> Why3.Ptree.term option

(** [compile_hexpr env h] compiles a Kairos historical expression to a Why3
    term.

    - [~old]: when [true], wraps variables in [old()] (for postconditions).
    - [~prefer_link]: when [true], uses the linked invariant predicate instead
      of expanding the expression.
    - [~in_post]: signals compilation inside a postcondition. *)
val compile_hexpr :
  ?old:bool -> ?prefer_link:bool -> ?in_post:bool -> env -> Core_syntax.hexpr -> Why3.Ptree.term

(** [compile_fo_term env atom] compiles a Kairos first-order atom to a Why3
    term. *)
val compile_fo_term : ?prefer_link:bool -> env -> Core_syntax.fo_atom -> Why3.Ptree.term

(** [compile_local_fo_formula_term env f] compiles a canonical first-order
    formula from the IR to a Why3 term. *)
val compile_local_fo_formula_term :
  ?prefer_link:bool -> ?in_post:bool -> env -> Fo_formula.t -> Why3.Ptree.term

(** [compile_fo_term_shift env in_old atom] compiles a first-order atom
    applying the temporal shift. *)
val compile_fo_term_shift :
  ?prefer_link:bool -> ?in_post:bool -> env -> bool -> Core_syntax.fo_atom -> Why3.Ptree.term

(** [pre_k_source_expr env x] builds the WhyML source expression for a k-step
    history variable initialisation. *)
val pre_k_source_expr : env -> Core_syntax.ident -> Why3.Ptree.expr

(** [pre_k_source_term env x] builds the logical source term for a k-step
    history variable. *)
val pre_k_source_term : env -> Core_syntax.ident -> Why3.Ptree.term
