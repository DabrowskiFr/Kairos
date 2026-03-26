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

val build_formula_records : Ir.node list -> formula_record list
val formula_record_table : formula_record list -> (int, formula_record) Hashtbl.t
val stable_goal_id : int -> int list -> string
val collect_origin_ids : int list -> int list

val resolve_formula_record :
  records:(int, formula_record) Hashtbl.t -> why_ids:int list -> formula_record option

val source_from_record_or_state :
  record:formula_record option ->
  state_pair:(string * string) option ->
  obc_program:Ast.program ->
  string

val lookup_span : ('a, 'b) Hashtbl.t -> 'a -> 'b option
val vc_ids_of_task_goal_ids : int list list -> int list

val diagnostic_for_trace :
  status:string ->
  record:formula_record option ->
  goal_text:string ->
  structured_sequent:Why_contract_prove.structured_sequent option ->
  failing_core:Why_contract_prove.failing_hypothesis_core option ->
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
