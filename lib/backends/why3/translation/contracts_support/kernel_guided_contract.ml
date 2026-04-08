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

open Ast

type temporal_binding_ir = {
  source_hexpr : Ast.hexpr;
  source_expr : Ast.iexpr;
  slot_names : Ast.ident list;
}

type exported_summary_contract = {
  node_name : Ast.ident;
  input_names : Ast.ident list;
  output_names : Ast.ident list;
  user_invariants : Ast.invariant_user list;
  state_invariants : Ast.invariant_state_rel list;
  temporal_bindings : temporal_binding_ir list;
}

type obligation_layers = {
  historical : Proof_kernel_types.generated_clause_ir list;
  eliminated : Proof_kernel_types.generated_clause_ir list;
  symbolic : Proof_kernel_types.relational_generated_clause_ir list;
}

type symbolic_obligation_groups = {
  source_product_summaries : Proof_kernel_types.relational_generated_clause_ir list;
  phase_steps : Proof_kernel_types.relational_generated_clause_ir list;
  propagation : Proof_kernel_types.relational_generated_clause_ir list;
  safety : Proof_kernel_types.relational_generated_clause_ir list;
}

type node_contract = {
  node_name : Ast.ident;
  product_coverage : Proof_kernel_types.product_coverage_ir;
  obligations : obligation_layers;
  symbolic_groups : symbolic_obligation_groups;
  proof_step_contracts : Proof_kernel_types.proof_step_contract_ir list;
  historical_clauses : Proof_kernel_types.generated_clause_ir list;
  eliminated_clauses : Proof_kernel_types.generated_clause_ir list;
  symbolic_clauses : Proof_kernel_types.relational_generated_clause_ir list;
}

let temporal_bindings_of_layout (temporal_layout : Ir.temporal_layout) :
    temporal_binding_ir list =
  List.map
    (fun (source_hexpr, (info : Temporal_support.pre_k_info)) ->
      let slot_names =
        match source_hexpr with
        | HPreK (_, k) when k > 0 && k <= List.length info.names -> [ List.nth info.names (k - 1) ]
        | HPreK _ -> []
        | HNow _ -> info.names
      in
      { source_hexpr; source_expr = info.expr; slot_names })
    temporal_layout

let exported_summary_of_exported_ir
    (summary : Proof_kernel_types.exported_node_summary_ir) : exported_summary_contract =
  {
    node_name = summary.signature.node_name;
    input_names = List.map (fun (v : Ast.vdecl) -> v.vname) summary.signature.inputs;
    output_names = List.map (fun (v : Ast.vdecl) -> v.vname) summary.signature.outputs;
    user_invariants = summary.user_invariants;
    state_invariants = [];
    temporal_bindings = temporal_bindings_of_layout summary.temporal_layout;
  }

let exported_summary_of_ast_node (node : Ast.node) : exported_summary_contract =
  {
    node_name = node.semantics.sem_nname;
    input_names = Ast_queries.input_names_of_node node;
    output_names = Ast_queries.output_names_of_node node;
    user_invariants = [];
    state_invariants = node.specification.spec_invariants_state_rel;
    temporal_bindings = temporal_bindings_of_layout (Collect.build_pre_k_infos node);
  }

let node_contract_of_ir (ir : Proof_kernel_types.node_ir) : node_contract =
  let obligations =
    {
      historical = ir.historical_generated_clauses;
      eliminated = ir.eliminated_generated_clauses;
      symbolic = ir.symbolic_generated_clauses;
    }
  in
  let symbolic_groups =
    {
      source_product_summaries =
        List.filter
          (fun clause -> clause.Proof_kernel_types.origin = Proof_kernel_types.OriginSourceProductSummary)
          obligations.symbolic;
      phase_steps =
        List.filter
          (fun clause -> clause.Proof_kernel_types.origin = Proof_kernel_types.OriginPhaseStepSummary)
          obligations.symbolic;
      propagation =
        List.filter
          (fun clause ->
            clause.Proof_kernel_types.origin = Proof_kernel_types.OriginPropagationNodeInvariant
            || clause.Proof_kernel_types.origin = Proof_kernel_types.OriginPropagationAutomatonCoherence)
          obligations.symbolic;
      safety =
        List.filter
          (fun clause -> clause.Proof_kernel_types.origin = Proof_kernel_types.OriginSafety)
          obligations.symbolic;
    }
  in
  {
    node_name = ir.reactive_program.node_name;
    product_coverage = ir.product_coverage;
    obligations;
    symbolic_groups;
    proof_step_contracts = ir.proof_step_contracts;
    historical_clauses = obligations.historical;
    eliminated_clauses = obligations.eliminated;
    symbolic_clauses = obligations.symbolic;
  }

let latest_slot_name_for_hexpr (summary : exported_summary_contract) (h : Ast.hexpr) :
    Ast.ident option =
  summary.temporal_bindings
  |> List.find_map (fun binding ->
         if binding.source_hexpr = h then
           match List.rev binding.slot_names with
           | name :: _ -> Some name
           | [] -> None
         else None)

let first_slot_name_for_input (summary : exported_summary_contract) (input_name : Ast.ident) :
    Ast.ident option =
  summary.temporal_bindings
  |> List.find_map (fun binding ->
         match (binding.source_expr.iexpr, binding.slot_names) with
         | IVar x, first :: _ when x = input_name -> Some first
         | _ -> None)
