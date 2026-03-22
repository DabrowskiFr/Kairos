(** Stable naming and lightweight string render helpers for kernel/product IR. *)

val phase_state_case_name : prog_state:Ast.ident -> guarantee_state:int -> string
val phase_step_pre_case_name : Proof_kernel_types.product_step_ir -> string
val phase_step_post_case_name : Proof_kernel_types.product_step_ir -> string

val string_of_role : Proof_kernel_types.automaton_role -> string
val string_of_step_kind : Proof_kernel_types.product_step_kind -> string
val string_of_step_origin : Proof_kernel_types.product_step_origin -> string
val string_of_product_coverage : Proof_kernel_types.product_coverage_ir -> string
val string_of_clause_origin : Proof_kernel_types.generated_clause_origin -> string
val string_of_clause_time : Proof_kernel_types.clause_time_ir -> string
val string_of_call_port_role : Proof_kernel_types.call_port_role -> string
val string_of_call_binding_kind : Proof_kernel_types.call_binding_kind -> string
val string_of_call_fact_kind : Proof_kernel_types.call_fact_kind -> string
val string_of_clause_fact_desc : Proof_kernel_types.clause_fact_desc_ir -> string
val string_of_relational_clause_fact_desc :
  Proof_kernel_types.relational_clause_fact_desc_ir -> string
val string_of_clause_fact : Proof_kernel_types.clause_fact_ir -> string
val string_of_relational_clause_fact : Proof_kernel_types.relational_clause_fact_ir -> string
val string_of_call_fact : Proof_kernel_types.call_fact_ir -> string
val string_of_product_state : Proof_kernel_types.product_state_ir -> string
val string_of_edge : Proof_kernel_types.automaton_edge_ir -> string
