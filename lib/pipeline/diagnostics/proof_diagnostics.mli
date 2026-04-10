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

(** Proof diagnostics and obligation/source traceability helpers. *)

type formula_record = {
  oid : int;
  source : string;
  node : string option;
  transition : string option;
  obligation_kind : string;
  obligation_family : string option;
  obligation_category : string option;
  loc : Ast.loc option;
}

val build_formula_records : Ir.node_ir list -> formula_record list
val formula_record_table : formula_record list -> (int, formula_record) Hashtbl.t
val stable_goal_id : int -> int list -> string
val collect_origin_ids : int list -> int list

val resolve_formula_record :
  records:(int, formula_record) Hashtbl.t -> why_ids:int list -> formula_record option

val source_from_record_or_state : record:formula_record option -> string

val lookup_span : ('a, 'b) Hashtbl.t -> 'a -> 'b option
val vc_ids_of_task_goal_ids : int list list -> int list

val diagnostic_for_trace :
  status:string ->
  record:formula_record option ->
  goal_text:string ->
  native_core:Why_contract_prove.native_unsat_core option ->
  native_probe:Why_contract_prove.native_solver_probe option ->
  Pipeline_types.proof_diagnostic

val generic_diagnostic_for_status :
  status:string ->
  Pipeline_types.proof_diagnostic ->
  Pipeline_types.proof_diagnostic

val apply_goal_results_to_outputs :
  out:Pipeline_types.outputs ->
  goal_results:(int * string * string * float * string option * string * string option) list ->
  Pipeline_types.outputs
