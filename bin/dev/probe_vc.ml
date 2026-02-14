open Pipeline
open Why_prove
module Abs = Abstract_model

let build_formula_sources_abs (p_obc : Abs.node list) : (int * string) list =
  let acc = ref [] in
  List.iter
    (fun (node : Abs.node) ->
      List.iter
        (fun (goal : Ast.fo_o) ->
          acc := (goal.oid, Printf.sprintf "%s: <no transition>" node.nname) :: !acc)
        node.attrs.coherency_goals;
      List.iter
        (fun (t : Abs.transition) ->
          let src = Printf.sprintf "%s: %s -> %s" node.nname t.src t.dst in
          List.iter (fun (ens : Ast.fo_o) -> acc := (ens.oid, src) :: !acc) t.ensures)
        node.trans)
    p_obc;
  List.rev !acc

let build_vc_sources_from_formula_sources ~(formula_sources : (int * string) list)
    ~(vc_ids_ordered : int list) : (int * string) list =
  let src_tbl = Hashtbl.create (List.length formula_sources * 2) in
  List.iter (fun (k, v) -> Hashtbl.replace src_tbl k v) formula_sources;
  List.map
    (fun vcid ->
      let ids = vcid :: Provenance.ancestors vcid in
      let source =
        ids
        |> List.find_map (fun id -> Hashtbl.find_opt src_tbl id)
        |> Option.value ~default:""
      in
      (vcid, source))
    vc_ids_ordered

let () =
  if Array.length Sys.argv < 2 then (prerr_endline "usage"; exit 2);
  let file = Sys.argv.(1) in
  match Pipeline.build_ast ~input_file:file () with
  | Error e -> Printf.printf "AST ERROR: %s\n" (Pipeline.error_to_string e)
  | Ok asts ->
      let p_obc = List.map Abstract_model.to_ast_node asts.obc_abstract in
      let obc_abs = List.map Abs.of_ast_node p_obc in
      let why_text = Io.emit_why ~prefix_fields:false ~output_file:None p_obc in
      let pairs = Why_prove.task_state_pairs ~text:why_text in
      Printf.printf "pairs=%d\n" (List.length pairs);
      List.iteri (fun i p -> if i<30 then match p with None->Printf.printf "%d: none\n" i | Some (a,b)->Printf.printf "%d: %s -> %s\n" i a b) pairs;
      let seqs = Why_prove.task_sequents ~text:why_text in
      let wids = Why_prove.task_goal_wids ~text:why_text in
      Printf.printf "seqs=%d\n" (List.length seqs);
      List.iteri (fun i (_h,g) -> if i<10 then Printf.printf "G%d %s\n" i g) seqs
      ;
      Printf.printf "wids=%d\n" (List.length wids);
      List.iteri
        (fun i ws ->
          if i < 20 then
            Printf.printf "W%d [%s]\n" i (String.concat "," (List.map string_of_int ws)))
        wids
      ;
      let tasks = Why_prove.dump_why3_tasks_with_attrs ~text:why_text in
      Printf.printf "tasks=%d\n" (List.length tasks);
      let contains_sub s sub =
        let ls = String.length s in
        let lsub = String.length sub in
        let rec aux i =
          if i + lsub > ls then false
          else if String.sub s i lsub = sub then true
          else aux (i + 1)
        in
        if lsub = 0 then true else aux 0
      in
      let with_attrs =
        List.fold_left (fun acc t -> if contains_sub t "(* attrs " then acc + 1 else acc) 0 tasks
      in
      Printf.printf "tasks_with_attrs=%d\n" with_attrs;
      begin
        match tasks with
        | t0 :: _ ->
            let lines = String.split_on_char '\n' t0 in
            List.iteri (fun i l -> if i < 40 then Printf.printf "T0:%s\n" l) lines
        | [] -> ()
      end
      ;
      let printed = ref 0 in
      List.iteri
        (fun i t ->
          if !printed < 20 then
            let lines = String.split_on_char '\n' t in
            List.iter
              (fun l ->
                if !printed < 20 && contains_sub l "(* attrs " then (
                  Printf.printf "A%d:%s\n" i l;
                  incr printed))
              lines)
        tasks
      ;
      let formula_sources = build_formula_sources_abs obc_abs in
      let vc_ids_ordered =
        List.map
          (fun ws ->
            let id = Provenance.fresh_id () in
            Provenance.add_parents ~child:id ~parents:ws;
            id)
          wids
      in
      let vc_sources = build_vc_sources_from_formula_sources ~formula_sources ~vc_ids_ordered in
      let counts = Hashtbl.create 16 in
      List.iter
        (fun (_id, src) ->
          let k = String.trim src in
          let n = Hashtbl.find_opt counts k |> Option.value ~default:0 in
          Hashtbl.replace counts k (n + 1))
        vc_sources;
      Printf.printf "source_groups=%d\n" (Hashtbl.length counts);
      Hashtbl.to_seq counts |> List.of_seq
      |> List.sort (fun (_a,na) (_b,nb) -> compare nb na)
      |> List.iteri (fun i (k,n) -> if i < 20 then Printf.printf "S%d %d %s\n" i n k)
