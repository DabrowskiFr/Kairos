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

(** Evaluation support for LTL-style formulas over finite valuation contexts. *)

(** {1 Valuation Helpers} *)

(** Compact label for a valuation, using assignments such as [x=0,y=1]. *)
val valuation_label : (string * bool) list -> string

(** Implicant representation used by boolean minimization. *)
type term = (string * bool option) list

(** Lookup a boolean value in a valuation, defaulting to [false]. *)
val lookup_val : (string * bool) list -> string -> bool

(** Build a minterm from a valuation. *)
val term_of_vals : string list -> (string * bool) list -> term

(** Decide whether two minterms can be merged. *)
val can_merge_terms : term -> term -> bool

(** Merge two minterms into a more general implicant. *)
val merge_terms : term -> term -> term

(** Remove duplicate implicants. *)
val uniq_terms : term list -> term list

(** Compute prime implicants by repeated merging. *)
val prime_implicants : term list -> term list

(** Decide whether an implicant covers a valuation. *)
val term_covers : term -> (string * bool) list -> bool

(** Choose implicants that cover all valuations. *)
val choose_implicants : string list -> (string * bool) list list -> term list

(** Render an implicant as a boolean formula string. *)
val term_to_string : term -> string

(** Build a simplified boolean formula string covering the given valuations. *)
val valuations_to_formula : string list -> (string * bool) list list -> string

(** Convert an implicant into an immediate expression. *)
val term_to_iexpr : term -> Ast.iexpr

(** Convert a disjunction of implicants into an immediate expression. *)
val terms_to_iexpr : term list -> Ast.iexpr

(** Build an immediate-expression formula covering the given valuations. *)
val valuations_to_iexpr : string list -> (string * bool) list list -> Ast.iexpr
