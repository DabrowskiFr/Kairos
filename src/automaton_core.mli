(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

(** {1 DOT Helpers} *)

(** Escape a string for DOT node/edge labels. *)
val escape_dot_label : string -> string

(** {1 Valuations And Boolean Minimization} *)

(** Escape a string for DOT quoted labels. *)
val all_valuations : string list -> (string * bool) list list
(** Enumerate all boolean valuations for a list of atom names. *)
val valuation_label : (string * bool) list -> string
(** Compact label for a valuation (name=0/1). *)
type term = (string * bool option) list
(** Compute lookup val. *)
val lookup_val : (string * bool) list -> string -> bool
(** Lookup a boolean value in a valuation (default false). *)
val term_of_vals : string list -> (string * bool) list -> term
(** Build a minterm from a valuation. *)
val can_merge_terms : term -> term -> bool
(** Check if two minterms can be merged (differ in one literal). *)
val merge_terms : term -> term -> term
(** Merge two minterms into a more general implicant. *)
val uniq_terms : term list -> term list
(** Remove duplicate implicants. *)
val prime_implicants : term list -> term list
(** Compute prime implicants by merging minterms. *)
val term_covers : term -> (string * bool) list -> bool
(** True if an implicant covers a valuation. *)
val choose_implicants : string list -> (string * bool) list list -> term list
(** Choose implicants that cover all valuations. *)
val term_to_string : term -> string
(** Render an implicant as a boolean formula string. *)
val valuations_to_formula :
  string list -> (string * bool) list list -> string
(** Build a simplified boolean formula string for valuations. *)
(** {1 Formula Conversion} *)

val term_to_iexpr : term -> Ast.iexpr
(** Convert an implicant into an iexpr. *)
val terms_to_iexpr : term list -> Ast.iexpr
(** Convert a disjunction of implicants into an iexpr. *)
val valuations_to_iexpr :
  string list -> (string * bool) list list -> Ast.iexpr
(** Build an iexpr formula covering valuations. *)
(** {1 LTL Normalization} *)

val nnf_ltl : ?neg:bool -> Ast.ltl -> Ast.ltl
(** Convert an LTL formula into negation normal form. *)
val simplify_ltl : Ast.ltl -> Ast.ltl
(** Simplify LTL formulas via boolean rewrites. *)
val eval_atom :
  (Ast.fo * Ast.ident) list -> (string * bool) list -> Ast.fo -> bool
(** Evaluate an atom against a valuation. *)
(** {1 Residual Automaton} *)

val progress_ltl :
  (Ast.fo * Ast.ident) list -> (string * bool) list -> Ast.ltl -> Ast.ltl
(** Progress an LTL formula through one valuation. *)
type residual_state = Ast.ltl
type residual_transition = int * (string * bool) list * int
(** Build residual graph. *)
val build_residual_graph :
  (Ast.fo * Ast.ident) list ->
  (string * bool) list list ->
  Ast.ltl -> residual_state list * residual_transition list
(** Build the residual automaton for an LTL formula. *)
val minimize_residual_graph :
  (string * bool) list list ->
  residual_state list ->
  residual_transition list -> residual_state list * residual_transition list
(** Minimize the residual automaton by partition refinement. *)
