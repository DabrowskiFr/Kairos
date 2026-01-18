
open Ast

let rec shift_hexpr_forward ~(init_for_var:ident -> iexpr) ~(is_input:ident -> bool) (h:hexpr) : hexpr =
  match h with
  | HNow (IVar v) when is_input v ->
      HPreK (IVar v, init_for_var v, 1)
  | HNow _ -> h
  | HPre (IVar v, init_opt) ->
      let init = Option.value init_opt ~default:(init_for_var v) in
      HPreK (IVar v, init, 2)
  | HPre (e, Some init) ->
      HPreK (e, init, 2)
  | HPre (e, None) ->
      HPre (e, None)
  | HPreK (e, init, k) ->
      HPreK (e, init, k + 1)
  | HLet (id, h1, h2) ->
      HLet (id, shift_hexpr_forward ~init_for_var ~is_input h1,
            shift_hexpr_forward ~init_for_var ~is_input h2)
  | HScan1 _ | HScan _ | HFold _ | HWindow _ -> h

let rec shift_ltl_forward_inputs ~(init_for_var:ident -> iexpr) ~(is_input:ident -> bool) (f:ltl) : ltl =
  match f with
  | LTrue | LFalse -> f
  | LNot a -> LNot (shift_ltl_forward_inputs ~init_for_var ~is_input a)
  | LAnd (a, b) ->
      LAnd (shift_ltl_forward_inputs ~init_for_var ~is_input a,
            shift_ltl_forward_inputs ~init_for_var ~is_input b)
  | LOr (a, b) ->
      LOr (shift_ltl_forward_inputs ~init_for_var ~is_input a,
           shift_ltl_forward_inputs ~init_for_var ~is_input b)
  | LImp (a, b) ->
      LImp (shift_ltl_forward_inputs ~init_for_var ~is_input a,
            shift_ltl_forward_inputs ~init_for_var ~is_input b)
  | LX a -> LX (shift_ltl_forward_inputs ~init_for_var ~is_input a)
  | LG a -> LG (shift_ltl_forward_inputs ~init_for_var ~is_input a)
  | LAtom (ARel (h1, r, h2)) ->
      LAtom (ARel (shift_hexpr_forward ~init_for_var ~is_input h1, r,
                   shift_hexpr_forward ~init_for_var ~is_input h2))
  | LAtom (APred (id, hs)) ->
      LAtom (APred (id, List.map (shift_hexpr_forward ~init_for_var ~is_input) hs))

let conj_ltl (fs:ltl list) : ltl option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> LAnd (acc, x)) f rest)

let add_post_for_next_pre (n:node) : node =
  let init_for_var =
    let table =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> ILitBool false
      | Some TInt -> ILitInt 0
      | Some TReal -> ILitInt 0
      | Some (TCustom _) | None -> ILitInt 0
  in
  let node_ensures =
    List.filter_map
      (function
        | Ensures f | Guarantee f -> Some f
        | _ -> None)
      n.contracts
  in
  let succ_requires_by_state : (ident, ltl list) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (t:transition) ->
      List.iter
        (function
          | Requires f ->
              let existing =
                Hashtbl.find_opt succ_requires_by_state t.src
                |> Option.value ~default:[]
              in
              Hashtbl.replace succ_requires_by_state t.src (f :: existing)
          | _ -> ())
        t.contracts)
    n.trans;
  let uniq lst =
    List.sort_uniq compare lst
  in
  let trans =
    List.map
      (fun (t:transition) ->
        let succ_reqs =
          Hashtbl.find_opt succ_requires_by_state t.dst
          |> Option.value ~default:[]
          |> uniq
        in
        let trans_ensures =
          List.filter_map
            (function
              | Ensures f | Guarantee f -> Some f
              | _ -> None)
            t.contracts
        in
        let ensures_all = node_ensures @ trans_ensures in
        let new_lemmas =
          match conj_ltl ensures_all with
          | None -> []
          | Some ensures_conj ->
              let is_input v = List.exists (fun vi -> vi.vname = v) n.inputs in
              let ensures_shifted =
                shift_ltl_forward_inputs ~init_for_var ~is_input ensures_conj
              in
              let has_lemma f =
                List.exists
                  (function
                    | Lemma f' -> f' = f
                    | _ -> false)
                  t.contracts
              in
              succ_reqs
              |> List.map (fun req -> LImp (ensures_shifted, req))
              |> List.filter (fun f -> not (has_lemma f))
              |> List.map (fun f -> Lemma f)
        in
        if new_lemmas = [] then t
        else { t with contracts = t.contracts @ new_lemmas })
      n.trans
  in
  { n with trans }

let add_post_for_next_pre_program (p:program) : program =
  List.map add_post_for_next_pre p

let parse_file (fn:string) : program =
  let ic = open_in fn in
  let lb = Lexing.from_channel ic in
  try
    let p = Parser.program Lexer.token lb in
    close_in ic; p
  with e ->
    let pos = lb.lex_curr_p in
    Printf.eprintf "Parse error at %s:%d:%d\n"
      pos.pos_fname pos.pos_lnum (pos.pos_cnum - pos.pos_bol);
    close_in_noerr ic;
    raise e

let () =
  let use_monitor = ref true in
  let monitor_dot = ref None in
  let monitor_no_prefix = ref true in
  let no_prefix = ref false in
  let show_help = ref false in
  let k_induction = ref false in
  let prove = ref false in
  let prover = ref "z3" in
  let vc_all = ref false in
  let output_file = ref None in
  let files = ref [] in
  let usage =
    "Usage: obc2why3 [--monitor] [--k-induction]\n" ^
    "                [--monitor-dot <file.dot>]\n" ^
    "                [-o <file.why>]\n" ^
    "                [--prove --prover <name>] <file.obc>\n" ^
    "Options:\n" ^
    "  --help               Show this help message\n" ^
    "  --monitor            Generate Why3 using a monitor state for residuals (default)\n" ^
    "  --monitor-no-prefix  Do not prefix vars fields with the module name (monitor mode, default)\n" ^
    "  --no-prefix          Do not prefix vars fields with the module name (monitor mode, default)\n" ^
    "  --monitor-dot        Generate DOT for the monitor residual graph and print Why3\n" ^
    "  -o <file.why>        Write generated Why3 to this file\n" ^
    "  --k-induction        Generate k-induction proof obligations for X^k under G\n" ^
    "  --prove              Run why3 prove on the generated output\n" ^
    "  -vc-all              Show results for all VCs (split VC)\n" ^
    "  --prover <name>      Prover for --prove (default: z3)\n"
  in
  let i = ref 1 in
  while !i < Array.length Sys.argv do
    match Sys.argv.(!i) with
    | "--help" ->
        show_help := true;
        incr i
    | "--monitor-no-prefix" ->
        monitor_no_prefix := true;
        incr i
    | "--no-prefix" ->
        no_prefix := true;
        incr i
    | "--monitor" ->
        use_monitor := true;
        incr i
    | "--monitor-dot" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --monitor-dot";
          exit 1
        ) else (
          monitor_dot := Some Sys.argv.(!i + 1);
          i := !i + 2
        )
    | "--k-induction" ->
        k_induction := true;
        incr i
    | "--prove" ->
        prove := true;
        incr i
    | "-vc-all" ->
        vc_all := true;
        incr i
    | "-o" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for -o";
          exit 1
        ) else (
          output_file := Some Sys.argv.(!i + 1);
          i := !i + 2
        )
    | "--prover" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --prover";
          exit 1
        ) else (
          prover := Sys.argv.(!i + 1);
          i := !i + 2
        )
    | arg when String.length arg > 0 && arg.[0] = '-' ->
        prerr_endline ("Unknown option: " ^ arg);
        exit 1
    | arg ->
        files := arg :: !files;
        incr i
  done;
  if !show_help then (
    print_string usage;
    exit 0
  );
  if !no_prefix then (
    monitor_no_prefix := true
  );
  match List.rev !files with
  | [file] ->
      let p = parse_file file |> add_post_for_next_pre_program in
      let output_and_maybe_prove out =
        let output_path =
          match !output_file with
          | Some path ->
              let oc = open_out path in
              output_string oc out;
              close_out oc;
              Some path
          | None -> None
        in
        if !prove then (
          let prove_path, remove_after =
            match output_path with
            | Some path -> (path, false)
            | None ->
                let tmp = Filename.temp_file "obc2why3_" ".why" in
                let oc = open_out tmp in
                output_string oc out;
                close_out oc;
                (tmp, true)
          in
          let action =
            if !vc_all then "-a split_vc "
            else ""
          in
          let cmd =
            Printf.sprintf "why3 prove -P %s -t 30 %s%s"
              !prover action (Filename.quote prove_path)
          in
          let status = Sys.command cmd in
          if remove_after then Sys.remove prove_path;
          if status <> 0 then exit status
        );
        if output_path = None then print_string out
      in
      begin match !monitor_dot with
      | Some out_file ->
          let residual_file =
            if Filename.check_suffix out_file ".dot"
            then out_file
            else out_file ^ ".dot"
          in
          let write path content =
            let oc = open_out path in
            output_string oc content;
            close_out oc
          in
          write residual_file (Whygen_automaton.dot_monitor_program p);
          let out =
            Whygen_automaton.compile_program_monitor
              ~k_induction:!k_induction
              ~prefix_fields:(not !monitor_no_prefix)
              p
          in
          output_and_maybe_prove out
      | None ->
          let out =
            if !use_monitor then
              Whygen_automaton.compile_program_monitor
                ~k_induction:!k_induction
                ~prefix_fields:(not !monitor_no_prefix)
                p
            else
              Whygen_automaton.compile_program_monitor
                ~k_induction:!k_induction
                ~prefix_fields:(not !monitor_no_prefix)
                p
          in
          output_and_maybe_prove out
      end
  | _ ->
      prerr_endline usage;
      exit 1
