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

(** Loads imported [.kobj] objects and their exported node summaries. *)

type loaded_imports = {
  objects : Kairos_object.t list;
  summaries : Proof_kernel_types.exported_node_summary_ir list;
  resolved_paths : string list;
}

val load_for_source :
  source_path:string ->
  source:Source_file.t ->
  (loaded_imports, string) result

val object_output_path_of_source : string -> string
