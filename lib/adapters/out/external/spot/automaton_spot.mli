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

(** Spot adapter interface for safety automata.

    This module defines the typed data extracted from HOA files and the
    conversion helpers used by the automata-generation pipeline. *)

open Ast

(** Result of one external process execution. *)
type process_result = {
  status : Unix.process_status;
  stdout : string;
  stderr : string;
}

(** Boolean label language used in HOA transitions. *)
type label_expr =
  | Label_true
  | Label_false
  | Label_var of int
  | Label_not of label_expr
  | Label_and of label_expr * label_expr
  | Label_or of label_expr * label_expr

(** One HOA state with accepting flag and outgoing transitions. *)
type hoa_state = {
  id : int;
  accepting : bool;
  transitions : (label_expr * int) list;
}

(** Acceptance mode supported by this parser. *)
type acceptance =
  | Acceptance_all
  | Acceptance_buchi

(** Parsed HOA automaton used downstream by product construction. *)
type hoa_automaton = {
  start : int;
  ap_count : int;
  ap_names : string list;
  acceptance : acceptance;
  states : hoa_state list;
}

(** Disjunction of conjunctions over named atoms.

    A literal [(name, Some true)] means [name];
    [(name, Some false)] means [not name];
    [(name, None)] means unconstrained/neutral. *)
type raw_guard = (string * bool option) list list

(** Whether Spot debug logging is enabled by environment. *)
val automata_log_enabled : bool

(** Render a Kairos LTL formula into Spot syntax with the given atom map. *)
val string_of_spot_ltl :
  atom_map:(Core_syntax.ltl_atom * Core_syntax.ident) list ->
  Core_syntax.ltl ->
  string

(** Fail if Spot reports that the queried formula is not a safety formula. *)
val ensure_safety : string -> unit

(** Run Spot and return the process standard output. *)
val call_spot : string -> string

(** Parse a Spot HOA output into a typed automaton. *)
val parse_hoa : string -> hoa_automaton

(** Convert one HOA label into the internal raw-guard representation. *)
val raw_guard_of_label :
  atom_names:string list -> hoa_ap_names:string list -> label_expr -> raw_guard

(** Tautological raw guard over the given atom domain. *)
val raw_guard_true : string list -> raw_guard

(** Merge two raw guards with disjunction semantics. *)
val merge_raw_guards : raw_guard -> raw_guard -> raw_guard
