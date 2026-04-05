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

(** Helpers to dump and emit intermediate pipeline artifacts. *)

val write_text : string -> string -> unit
(* Write raw text content to a file path. *)

val dump_ast_stage :
  stage:Stage_names.stage_id ->
  out:string option ->
  stable:bool ->
  Ast.program ->
  (unit, string) result
(* Dump a single AST stage to a file or stdout. *)

val dump_ast_all :
  dir:string ->
  parsed:Ast.program ->
  automaton:Ast.program ->
  contracts:Ast.program ->
  instrumentation:Ast.program ->
  stable:bool ->
  (unit, string) result
(* Dump all AST stages to a directory (one file per stage). *)

val emit_dot_files : show_labels:bool -> out_file:string -> Ast.program -> unit
(* Emit DOT graph files for a program. *)

val emit_why3_vc : out_file:string -> why_text:string -> unit
(* Emit Why3 VCs to a file (text is already generated). *)

val emit_smt2 : out_file:string -> prover:string -> why_text:string -> unit
(* Emit SMT2 tasks to a file using a prover driver. *)


val prove_why : prover:string -> prover_cmd:string option -> why_text:string -> unit
(* Prove Why3 text using a prover driver. *)
