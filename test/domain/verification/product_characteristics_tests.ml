open Kr_domain_core.Kr_domain_core_syntax
open Kr_domain_core.Kr_domain_core_syntax_builders
open Kr_verification

let product_state assume_state_index guarantee_state_index : Kr_verification.Kr_verification_ir.product_state =
  {
    prog_state = "S";
    assume_state_index;
    guarantee_state_index;
  }

let summary_formula oid logic : Kr_domain_core.Kr_domain_core_syntax.historical Kr_verification.Kr_verification_ir.summary_formula =
  {
    logic;
    meta = { oid; loc = None; family = None };
  }

let transition : Kr_verification.Kr_verification_ir.transition =
  {
    src_state = "S";
    dst_state = "S";
    guard_expr = None;
    body_stmts = [];
  }

let summary ~step_uid ~(src : Kr_verification.Kr_verification_ir.product_state)
    ~assume_destination_state_index
    product_cases :
    Kr_domain_core.Kr_domain_core_syntax.historical Kr_verification.Kr_verification_ir.product_step_summary =
  {
    trace = { step_uid };
    identity =
      {
        program_step = transition;
        monitor_source =
          {
            assume_state_index = src.assume_state_index;
            guarantee_state_index =
              src.guarantee_state_index;
          };
        assume_destination_state_index;
        assume_guard = mk_hbool true;
      };
    propagation_requires = [];
    requires = [];
    ensures = [];
    elaboration_checks = [];
    product_cases;
  }

let test_exact_initial_state_is_not_characterized () =
  let actual_initial = product_state 4 7 in
  let zero_indexed_state = product_state 0 0 in
  let incoming_case : Kr_domain_core.Kr_domain_core_syntax.historical Kr_verification.Kr_verification_ir.product_case =
    {
      guarantee_destination_state_index =
        actual_initial.guarantee_state_index;
      guarantee_guard = summary_formula 1 (mk_hvar "gate");
    }
  in
  let node : Kr_domain_core.Kr_domain_core_syntax.historical Kr_verification.Kr_verification_ir.node_ir =
    {
      semantics =
        {
          sem_nname = "nonzero_initial";
          sem_type_decls = [];
          sem_function_decls = [];
          sem_inputs = [ { vname = "gate"; vty = TBool } ];
          sem_outputs = [];
          sem_locals = [];
          sem_states = [ "S" ];
          sem_init_state = "S";
          sem_methods = [];
        };
      source_info =
        { assumes = []; guarantees = []; state_invariants = [] };
      temporal_layout = [];
      summaries =
        [
          summary ~step_uid:0 ~src:zero_indexed_state
            ~assume_destination_state_index:
              actual_initial.assume_state_index
            [ incoming_case ];
          summary ~step_uid:1 ~src:actual_initial
            ~assume_destination_state_index:
              actual_initial.assume_state_index
            [];
        ];
    }
  in
  let table_with_other_initial =
    Kr_verification_characteristics.build ~initial_state:zero_indexed_state
      ~node
  in
  assert (
    Kr_verification_characteristics.entry_facts_of_product_state
      table_with_other_initial actual_initial
    <> []);
  let table =
    Kr_verification_characteristics.build ~initial_state:actual_initial ~node
  in
  assert (
    Kr_verification_characteristics.entry_facts_of_product_state table
      actual_initial
    = [])

let () = test_exact_initial_state_is_not_characterized ()
