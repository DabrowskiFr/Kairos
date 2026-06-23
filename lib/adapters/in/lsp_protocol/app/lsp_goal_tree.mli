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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Group proof goals into the tree consumed by the LSP UI. *)

type goal_tree_entry = {
  idx : int;
  goal : string;
  status : string;
  time_s : float;
  dump_path : string option;
  source : string;
  vcid : string option;
}

type goal_tree_transition = {
  transition : string;
  source : string;
  succeeded : int;
  total : int;
  items : goal_tree_entry list;
}

type goal_tree_node = {
  node : string;
  source : string;
  succeeded : int;
  total : int;
  transitions : goal_tree_transition list;
}

val goals_tree_final :
  goals:Pipeline_types.goal_info list ->
  vc_text:string ->
  goal_tree_node list

val goals_tree_pending :
  goal_names:string list ->
  vc_ids:int list ->
  goal_tree_node list

val yojson_of_goals_tree : goal_tree_node list -> Yojson.Safe.t
