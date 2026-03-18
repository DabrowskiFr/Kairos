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

(* {1 Facade Module} Convenience re‑exports used by legacy code paths. Prefer the dedicated modules
   in [automaton_*] when writing new code. *)

(* Escape a string for DOT node/edge labels. *)
val escape_dot_label : string -> string

(* {1 Valuations And Boolean Minimization} *)

val automata_log_enabled : bool
(* True when monitor logging is enabled via [OBCWHY3_LOG_MONITOR]. *)

val valuation_label : (string * bool) list -> string

(* Compact label for a valuation (name=0/1). *)
type term = (string * bool option) list

(* Implicant representation for boolean minimization. *)
val lookup_val : (string * bool) list -> string -> bool

(* Lookup a boolean value in a valuation (default false). *)
val term_of_vals : string list -> (string * bool) list -> term

(* Build a minterm from a valuation. *)
val can_merge_terms : term -> term -> bool

(* Check if two minterms can be merged (differ in one literal). *)
val merge_terms : term -> term -> term

(* Merge two minterms into a more general implicant. *)
val uniq_terms : term list -> term list

(* Remove duplicate implicants. *)
val prime_implicants : term list -> term list

(* Compute prime implicants by merging minterms. *)
val term_covers : term -> (string * bool) list -> bool

(* True if an implicant covers a valuation. *)
val choose_implicants : string list -> (string * bool) list list -> term list

(* Choose implicants that cover all valuations. *)
val term_to_string : term -> string

(* Render an implicant as a boolean formula string. *)
val valuations_to_formula : string list -> (string * bool) list list -> string
(* Build a simplified boolean formula string for valuations. *)
(* {1 Formula Conversion} *)

val term_to_iexpr : term -> Ast.iexpr

(* Convert an implicant into an iexpr. *)
val terms_to_iexpr : term list -> Ast.iexpr

(* Convert a disjunction of implicants into an iexpr. *)
val valuations_to_iexpr : string list -> (string * bool) list list -> Ast.iexpr
(* Build an iexpr formula covering valuations. *)

val guard_to_formula : Automaton_types.guard -> string

(* Render a DNF guard as a boolean formula string. *)
val guard_to_iexpr : Automaton_types.guard -> Ast.iexpr
(* Convert a DNF guard into an iexpr formula. *)
type residual_state = Ast.fo_ltl
