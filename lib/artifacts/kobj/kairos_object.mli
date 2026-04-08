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

(** Serialized backend-agnostic Kairos object representation ([.kobj]). *)

type metadata = {
  format : string;
  format_version : int;
  backend_agnostic : bool;
  source_path : string option;
  source_hash : string option;
  imports : string list;
}
[@@deriving yojson]

type t = {
  metadata : metadata;
  nodes : Proof_kernel_types.exported_node_summary_ir list;
}
[@@deriving yojson]

val current_format : string
val current_version : int

val build :
  source_path:string ->
  source_hash:string option ->
  imports:string list ->
  program:Ast.program ->
  runtime_program:Ast.program ->
  kernel_ir_nodes:Proof_kernel_types.node_ir list ->
  (t, string) result

val summaries : t -> Proof_kernel_types.exported_node_summary_ir list
val render_summary : t -> string
val render_clauses : t -> string
val render_product : t -> string
val render_product_summaries : t -> string
val write_file : path:string -> t -> (unit, string) result
val read_file : path:string -> (t, string) result
