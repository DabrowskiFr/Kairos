open Ast
open Support
module Naming = Proof_kernel_naming

let render_reactive_program (p : Proof_kernel_ir.reactive_program_ir) : string list =
  let header =
    Printf.sprintf "reactive_program %s init=%s states=%d transitions=%d" p.node_name p.init_state
      (List.length p.states) (List.length p.transitions)
  in
  let states = List.map (fun st -> Printf.sprintf "  state %s" st) p.states in
  let transitions =
    List.map
      (fun (t : Proof_kernel_ir.reactive_transition_ir) ->
        Printf.sprintf "  trans %s -> %s guard=%s" t.src_state t.dst_state (string_of_ltl t.guard))
      p.transitions
  in
  header :: (states @ transitions)

let render_automaton (a : Proof_kernel_ir.safety_automaton_ir) : string list =
  let bad =
    match a.bad_state_index with None -> "none" | Some idx -> string_of_int idx
  in
  let header =
    Printf.sprintf "%s_automaton init=%d bad=%s states=%d edges=%d" (Naming.string_of_role a.role)
      a.initial_state_index bad (List.length a.state_labels) (List.length a.edges)
  in
  let states =
    List.map (fun (idx, lbl) -> Printf.sprintf "  state %d = %s" idx lbl) a.state_labels
  in
  let edges = List.map (fun edge -> "  edge " ^ Naming.string_of_edge edge) a.edges in
  header :: (states @ edges)

let render_generated_clause kind (clause : Proof_kernel_ir.generated_clause_ir) : string =
  let subject =
    match clause.anchor with
    | Proof_kernel_ir.ClauseAnchorProductState st -> Naming.string_of_product_state st
    | Proof_kernel_ir.ClauseAnchorProductStep step ->
        Printf.sprintf "%s -> %s" (Naming.string_of_product_state step.src)
          (Naming.string_of_product_state step.dst)
  in
  let hyps = String.concat ", " (List.map Naming.string_of_clause_fact clause.hypotheses) in
  let concls = String.concat ", " (List.map Naming.string_of_clause_fact clause.conclusions) in
  Printf.sprintf "  %s %s on %s if [%s] then [%s]" kind
    (Naming.string_of_clause_origin clause.origin) subject hyps concls

let render_historical_clauses (ir : Proof_kernel_ir.node_ir) : string list =
  List.map (render_generated_clause "historical_clause") ir.historical_generated_clauses

let render_eliminated_clauses (ir : Proof_kernel_ir.node_ir) : string list =
  List.map (render_generated_clause "eliminated_clause") ir.eliminated_generated_clauses

let render_product (ir : Proof_kernel_ir.node_ir) : string list =
  let header =
    Printf.sprintf "explicit_product initial=%s states=%d steps=%d historical=%d eliminated=%d symbolic=%d"
      (Naming.string_of_product_state ir.initial_product_state) (List.length ir.product_states)
      (List.length ir.product_steps) (List.length ir.historical_generated_clauses)
      (List.length ir.eliminated_generated_clauses)
      (List.length ir.symbolic_generated_clauses)
  in
  let coverage = Printf.sprintf "  coverage %s" (Naming.string_of_product_coverage ir.product_coverage) in
  let states = List.map (fun st -> "  pstate " ^ Naming.string_of_product_state st) ir.product_states in
  let steps =
    List.map
      (fun (step : Proof_kernel_ir.product_step_ir) ->
        Printf.sprintf
          "  pstep %s -- %s->%s / A[%d->%d] / G[%d->%d] --> %s [%s/%s]"
          (Naming.string_of_product_state step.src) (fst step.program_transition)
          (snd step.program_transition) step.assume_edge.src_index step.assume_edge.dst_index
          step.guarantee_edge.src_index step.guarantee_edge.dst_index
          (Naming.string_of_product_state step.dst) (Naming.string_of_step_kind step.step_kind)
          (Naming.string_of_step_origin step.step_origin))
      ir.product_steps
  in
  let historical_clauses = render_historical_clauses ir in
  let eliminated_clauses = render_eliminated_clauses ir in
  let symbolic_clauses =
    List.map
      (fun (clause : Proof_kernel_ir.relational_generated_clause_ir) ->
        let subject =
          match clause.anchor with
          | Proof_kernel_ir.ClauseAnchorProductState st -> Naming.string_of_product_state st
          | Proof_kernel_ir.ClauseAnchorProductStep step ->
              Printf.sprintf "%s -> %s" (Naming.string_of_product_state step.src)
                (Naming.string_of_product_state step.dst)
        in
        let hyps = String.concat ", " (List.map Naming.string_of_relational_clause_fact clause.hypotheses) in
        let concls = String.concat ", " (List.map Naming.string_of_relational_clause_fact clause.conclusions) in
        Printf.sprintf "  symbolic_clause %s on %s if [%s] then [%s]"
          (Naming.string_of_clause_origin clause.origin) subject hyps concls)
      ir.symbolic_generated_clauses
  in
  let instance_relations =
    List.map
      (function
        | Proof_kernel_ir.InstanceUserInvariant { instance_name; callee_node_name; invariant_id; _ } ->
            Printf.sprintf "  instance %s:%s user_invariant %s" instance_name callee_node_name
              invariant_id
        | Proof_kernel_ir.InstanceStateInvariant { instance_name; callee_node_name; state_name; is_eq; _ } ->
            Printf.sprintf "  instance %s:%s state_%s %s" instance_name callee_node_name
              (if is_eq then "eq" else "neq") state_name
        | Proof_kernel_ir.InstanceDelayHistoryLink
            { instance_name; callee_node_name; caller_output; callee_input; callee_pre_name } ->
            Printf.sprintf "  instance %s:%s delay_history %s <- old(%s)"
              instance_name callee_node_name caller_output
              (Option.value ~default:callee_input callee_pre_name)
        | Proof_kernel_ir.InstanceDelayCallerPreLink { caller_output; caller_pre_name } ->
            Printf.sprintf "  instance delay_caller_pre %s <- %s" caller_output caller_pre_name)
      ir.instance_relations
  in
  header
  :: (coverage
     :: (states @ steps @ historical_clauses @ eliminated_clauses @ symbolic_clauses
        @ instance_relations))

let render_call_summary_section (ir : Proof_kernel_ir.node_ir) : string list =
  let abi_header =
    Printf.sprintf "callee_tick_abis count=%d" (List.length ir.callee_tick_abis)
  in
  let abi_lines =
    List.concat_map
      (fun (abi : Proof_kernel_ir.callee_tick_abi_ir) ->
        let ports label ports =
          List.map
            (fun (port : Proof_kernel_ir.call_port_ir) ->
              Printf.sprintf "    %s_port %s (%s)" label port.port_name
                (Naming.string_of_call_port_role port.role))
            ports
        in
        let cases =
          List.concat_map
            (fun (case : Proof_kernel_ir.callee_summary_case_ir) ->
              let render_facts label facts =
                List.map
                  (fun fact -> Printf.sprintf "      %s %s" label (Naming.string_of_call_fact fact))
                  facts
              in
              ("    case " ^ case.case_name)
              :: (render_facts "entry" case.entry_facts
                 @ render_facts "transition" case.transition_facts
                 @ render_facts "exported" case.exported_post_facts))
            abi.cases
        in
        ("  callee_tick_abi " ^ abi.callee_node_name)
        :: (ports "input" abi.input_ports
           @ ports "output" abi.output_ports
           @ ports "state" abi.state_ports
           @ cases))
      ir.callee_tick_abis
  in
  let inst_header =
    Printf.sprintf "call_site_instantiations count=%d" (List.length ir.call_site_instantiations)
  in
  let inst_lines =
    List.concat_map
      (fun (inst : Proof_kernel_ir.call_site_instantiation_ir) ->
        let bindings =
          List.map
            (fun (binding : Proof_kernel_ir.call_binding_ir) ->
              Printf.sprintf "    binding %s %s -> %s"
                (Naming.string_of_call_binding_kind binding.binding_kind)
                binding.local_name binding.remote_name)
            inst.bindings
        in
        (Printf.sprintf "  call_site %s instance=%s callee=%s" inst.call_site_id inst.instance_name
           inst.callee_node_name)
        :: bindings)
      ir.call_site_instantiations
  in
  abi_header :: (abi_lines @ (inst_header :: inst_lines))

let render_call_summary_toy_example =
  let mk_fact fact_kind time desc =
    { Proof_kernel_ir.fact_kind; fact = { time; desc } }
  in
  let mk_eq lhs rhs =
    LAtom (FRel (HNow (Ast_builders.mk_var lhs), REq, HNow (Ast_builders.mk_var rhs)))
  in
  let abi =
    {
      Proof_kernel_ir.callee_node_name = "Delay";
      input_ports = [ { port_name = "x"; role = Proof_kernel_ir.CallInputPort } ];
      output_ports = [ { port_name = "y"; role = Proof_kernel_ir.CallOutputPort } ];
      state_ports = [ { port_name = "mem"; role = Proof_kernel_ir.CallStatePort } ];
      cases =
        [
          {
            case_name = "tick";
            entry_facts = [];
            transition_facts =
              [
                mk_fact Proof_kernel_ir.CallTransitionFact Proof_kernel_ir.CurrentTick
                  (Proof_kernel_ir.FactFormula (mk_eq "y" "mem_pre"));
                mk_fact Proof_kernel_ir.CallTransitionFact Proof_kernel_ir.CurrentTick
                  (Proof_kernel_ir.FactFormula (mk_eq "mem_post" "x"));
              ];
            exported_post_facts =
              [
                mk_fact Proof_kernel_ir.CallExportedPostFact Proof_kernel_ir.CurrentTick
                  (Proof_kernel_ir.FactFormula (mk_eq "mem_post" "x"));
              ];
          };
        ];
    }
  in
  let inst =
    {
      Proof_kernel_ir.instance_name = "d";
      call_site_id = "toy.delay.call.1";
      callee_node_name = "Delay";
      bindings =
        [
          { binding_kind = Proof_kernel_ir.BindActualInput; local_name = "a"; remote_name = "x" };
          { binding_kind = Proof_kernel_ir.BindActualOutput; local_name = "b"; remote_name = "y" };
          {
            binding_kind = Proof_kernel_ir.BindInstancePreState;
            local_name = "d_mem_pre";
            remote_name = "mem";
          };
          {
            binding_kind = Proof_kernel_ir.BindInstancePostState;
            local_name = "d_mem_post";
            remote_name = "mem";
          };
        ];
    }
  in
  let ir =
    {
      Proof_kernel_ir.reactive_program =
        { node_name = "toy"; init_state = "Init"; states = []; transitions = [] };
      assume_automaton =
        {
          role = Proof_kernel_ir.Assume;
          initial_state_index = 0;
          bad_state_index = None;
          state_labels = [];
          edges = [];
        };
      guarantee_automaton =
        {
          role = Proof_kernel_ir.Guarantee;
          initial_state_index = 0;
          bad_state_index = None;
          state_labels = [];
          edges = [];
        };
      initial_product_state = { prog_state = "Init"; assume_state_index = 0; guarantee_state_index = 0 };
      product_states = [];
      product_steps = [];
      product_coverage = Proof_kernel_ir.CoverageEmpty;
      historical_generated_clauses = [];
      eliminated_generated_clauses = [];
      symbolic_generated_clauses = [];
      proof_step_contracts = [];
      instance_relations = [];
      callee_tick_abis = [ abi ];
      call_site_instantiations = [ inst ];
      ghost_locals = [];
    }
  in
  "-- Toy call summary ABI example --" :: render_call_summary_section ir

let render_node_ir (ir : Proof_kernel_ir.node_ir) : string list =
  [ "-- Kernel-compatible pipeline IR --" ]
  @ render_reactive_program ir.reactive_program
  @ render_automaton ir.assume_automaton
  @ render_automaton ir.guarantee_automaton
  @ render_product ir
  @ render_call_summary_section ir
  @ render_call_summary_toy_example
