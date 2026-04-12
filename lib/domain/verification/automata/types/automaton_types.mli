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

(** Semantic automata data shared by the middle-end.

    This module describes:
    {ul
    {- semantic transition guards;}
    {- normalized automata;}
    {- per-node automata generation results.}} *)

(** Boolean guard carried by an automaton transition.

    Guards are stored as first-order formulas over history expressions. This
    preserves temporal structure such as [pre_k] through automata construction;
    lowering to materialized history variables happens later in the pipeline. *)
type guard = Core_syntax.hexpr

(** Transition represented as [(src_index, guard, dst_index)]. *)
type transition = int * guard * int

(** Safety automaton.

    The record contains:
    {ul
    {- the atom names used during automaton construction;}
    {- raw states and transitions;}
    {- normalized states and transitions;}
    {- grouped transitions for downstream consumers.}} *)
type automaton = {
  atom_names : Core_syntax.ident list;
  states_raw : Core_syntax.ltl list;
  transitions_raw : transition list;
  states : Core_syntax.ltl list;
  transitions : transition list;
  grouped : transition list;
}

(** Mapping between source-level atomic formulas and the fresh atom names used
    while building temporal automata. *)
type automata_atoms = {
  atom_map : ((Core_syntax.hexpr * Core_syntax.relop * Core_syntax.hexpr) * Core_syntax.ident) list;
  atom_named_exprs : (Core_syntax.ident * Core_syntax.expr) list;
}

(** Per-node automata generation result.

    A node carries:
    {ul
    {- one guarantee automaton;}
    {- zero or one assumption automaton;}
    {- the atom maps used to build them.}} *)
type automata_build = {
  atoms : automata_atoms;
  guarantee_atom_names : Core_syntax.ident list;
  guarantee_spec : Core_syntax.ltl;
  guarantee_automaton : automaton;
  assume_atoms : automata_atoms option;
  assume_atom_names : Core_syntax.ident list;
  assume_spec : Core_syntax.ltl option;
  assume_automaton : automaton option;
}

(** Program-wide collection of per-node automata builds, indexed by node name. *)
type node_builds = (Core_syntax.ident * automata_build) list
