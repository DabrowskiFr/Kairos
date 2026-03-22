open Ast

type eval_value =
  | VInt of int
  | VBool of bool
  | VReal of float
  | VCustom of string

let string_of_eval_value = function
  | VInt i -> string_of_int i
  | VBool b -> if b then "true" else "false"
  | VReal f -> string_of_float f
  | VCustom s -> s

let eval_error msg = Error (Pipeline_types.Stage_error ("eval: " ^ msg))

let default_value_of_ty = function
  | Ast.TInt -> VInt 0
  | Ast.TBool -> VBool false
  | Ast.TReal -> VReal 0.0
  | Ast.TCustom c -> VCustom c

let split_assignments (s : string) : string list =
  s |> String.split_on_char ',' |> List.map String.trim |> List.filter (fun x -> x <> "")

let strip_optional_quotes (s : string) : string =
  let s = String.trim s in
  let n = String.length s in
  if n >= 2 && s.[0] = '"' && s.[n - 1] = '"' then String.sub s 1 (n - 2) else s

let parse_typed_value ~(name : string) ~(ty : Ast.ty) (raw : string) :
    (eval_value, Pipeline_types.error) result =
  match ty with
  | Ast.TInt -> (
      match int_of_string_opt raw with
      | Some i -> Ok (VInt i)
      | None -> eval_error (Printf.sprintf "invalid int for '%s': %s" name raw))
  | Ast.TBool -> (
      match String.lowercase_ascii raw with
      | "true" | "1" -> Ok (VBool true)
      | "false" | "0" -> Ok (VBool false)
      | _ -> eval_error (Printf.sprintf "invalid bool for '%s': %s" name raw))
  | Ast.TReal -> (
      match float_of_string_opt raw with
      | Some f -> Ok (VReal f)
      | None -> eval_error (Printf.sprintf "invalid real for '%s': %s" name raw))
  | Ast.TCustom _ -> Ok (VCustom raw)

let eval_bool_of_value ~(ctx : string) = function
  | VBool b -> Ok b
  | v -> eval_error (Printf.sprintf "expected bool in %s, got '%s'" ctx (string_of_eval_value v))

let eval_int_of_value ~(ctx : string) = function
  | VInt i -> Ok i
  | v -> eval_error (Printf.sprintf "expected int in %s, got '%s'" ctx (string_of_eval_value v))

let eval_iexpr (env : (string, eval_value) Hashtbl.t) (e : Ast.iexpr) :
    (eval_value, Pipeline_types.error) result =
  let rec go (e : Ast.iexpr) : (eval_value, Pipeline_types.error) result =
    match e.iexpr with
    | ILitInt i -> Ok (VInt i)
    | ILitBool b -> Ok (VBool b)
    | IVar v -> (
        match Hashtbl.find_opt env v with
        | Some value -> Ok value
        | None -> eval_error (Printf.sprintf "unbound variable '%s'" v))
    | IPar e -> go e
    | IUn (Neg, e) -> (
        match go e with
        | Error _ as err -> err
        | Ok v -> (
            match eval_int_of_value ~ctx:"unary '-'" v with
            | Error _ as err -> err
            | Ok i -> Ok (VInt (-i))))
    | IUn (Not, e) -> (
        match go e with
        | Error _ as err -> err
        | Ok v -> (
            match eval_bool_of_value ~ctx:"unary 'not'" v with
            | Error _ as err -> err
            | Ok b -> Ok (VBool (not b))))
    | IBin (op, l, r) -> (
        match (go l, go r) with
        | (Error _ as err), _ -> err
        | _, (Error _ as err) -> err
        | Ok vl, Ok vr -> (
            match op with
            | Add | Sub | Mul | Div -> (
                match
                  ( eval_int_of_value ~ctx:"arithmetic lhs" vl,
                    eval_int_of_value ~ctx:"arithmetic rhs" vr )
                with
                | (Error _ as err), _ -> err
                | _, (Error _ as err) -> err
                | Ok li, Ok ri ->
                    if op = Div && ri = 0 then eval_error "division by zero"
                    else
                      let v =
                        match op with
                        | Add -> li + ri
                        | Sub -> li - ri
                        | Mul -> li * ri
                        | Div -> li / ri
                        | _ -> assert false
                      in
                      Ok (VInt v))
            | Eq -> Ok (VBool (vl = vr))
            | Neq -> Ok (VBool (vl <> vr))
            | Lt | Le | Gt | Ge -> (
                match
                  ( eval_int_of_value ~ctx:"comparison lhs" vl,
                    eval_int_of_value ~ctx:"comparison rhs" vr )
                with
                | (Error _ as err), _ -> err
                | _, (Error _ as err) -> err
                | Ok li, Ok ri ->
                    let b =
                      match op with
                      | Lt -> li < ri
                      | Le -> li <= ri
                      | Gt -> li > ri
                      | Ge -> li >= ri
                      | _ -> assert false
                    in
                    Ok (VBool b))
            | And | Or -> (
                match
                  ( eval_bool_of_value ~ctx:"logical lhs" vl,
                    eval_bool_of_value ~ctx:"logical rhs" vr )
                with
                | (Error _ as err), _ -> err
                | _, (Error _ as err) -> err
                | Ok lb, Ok rb -> Ok (VBool (if op = And then lb && rb else lb || rb)))))
  in
  go e

let eval_guard env (g : Ast.iexpr option) : (bool, Pipeline_types.error) result =
  match g with
  | None -> Ok true
  | Some e -> (
      match eval_iexpr env e with
      | Error _ as err -> err
      | Ok v -> eval_bool_of_value ~ctx:"transition guard" v)

let rec eval_stmt_list (env : (string, eval_value) Hashtbl.t) (stmts : Ast.stmt list) :
    (unit, Pipeline_types.error) result =
  match stmts with
  | [] -> Ok ()
  | s :: rest -> (
      match s.stmt with
      | SSkip -> eval_stmt_list env rest
      | SAssign (v, e) -> (
          match eval_iexpr env e with
          | Error _ as err -> err
          | Ok value ->
              Hashtbl.replace env v value;
              eval_stmt_list env rest)
      | SIf (c, tbr, fbr) -> (
          match eval_iexpr env c with
          | Error _ as err -> err
          | Ok cv -> (
              match eval_bool_of_value ~ctx:"if condition" cv with
              | Error _ as err -> err
              | Ok true -> (
                  match eval_stmt_list env tbr with
                  | Error _ as err -> err
                  | Ok () -> eval_stmt_list env rest)
              | Ok false -> (
                  match eval_stmt_list env fbr with
                  | Error _ as err -> err
                  | Ok () -> eval_stmt_list env rest)))
      | SMatch (e, branches, default) -> (
          match eval_iexpr env e with
          | Error _ as err -> err
          | Ok v ->
              let key = string_of_eval_value v in
              let selected =
                List.find_opt (fun (pat, _body) -> pat = key) branches
                |> Option.map snd
                |> Option.value ~default:default
              in
              (match eval_stmt_list env selected with
              | Error _ as err -> err
              | Ok () -> eval_stmt_list env rest))
      | SCall (inst, _args, _outs) ->
          eval_error
            (Printf.sprintf "calls not supported in evaluator yet (instance '%s')" inst))

let parse_trace_for_node ~(n : Ast.node) (trace_text : string) :
    ((string * eval_value) list list, Pipeline_types.error) result =
  let input_types =
    List.fold_left
      (fun m vd ->
        Hashtbl.replace m vd.vname vd.vty;
        m)
      (Hashtbl.create 16) n.semantics.sem_inputs
  in
  let lines =
    String.split_on_char '\n' trace_text
    |> List.map String.trim
    |> List.filter (fun l -> l <> "" && not (String.length l > 0 && l.[0] = '#'))
  in
  let parse_pairs idx pairs =
    let rec loop seen acc = function
      | [] -> Ok (List.rev acc)
      | (name, raw) :: rest ->
          let name = String.trim name in
          let raw = strip_optional_quotes raw in
          if name = "" then eval_error (Printf.sprintf "empty variable name at step %d" idx)
          else if Hashtbl.mem seen name then
            eval_error (Printf.sprintf "duplicate assignment for '%s' at step %d" name idx)
          else
            let () = Hashtbl.replace seen name true in
            let ty_opt = Hashtbl.find_opt input_types name in
            (match ty_opt with
            | None ->
                eval_error
                  (Printf.sprintf "unknown input '%s' at step %d (expected node inputs only)" name idx)
            | Some ty -> (
                match parse_typed_value ~name ~ty raw with
                | Error _ as err -> err
                | Ok v -> loop seen ((name, v) :: acc) rest))
    in
    match loop (Hashtbl.create 16) [] pairs with
    | Error _ as err -> err
    | Ok assigns ->
        let missing =
          n.semantics.sem_inputs
          |> List.filter_map (fun vd ->
                 if List.exists (fun (k, _) -> k = vd.vname) assigns then None else Some vd.vname)
        in
        if missing <> [] then
          eval_error
            (Printf.sprintf "missing input(s) at step %d: %s" idx (String.concat ", " missing))
        else Ok assigns
  in
  let parse_assign_line idx line =
    let chunks = split_assignments line in
    let rec to_pairs acc = function
      | [] -> Ok (List.rev acc)
      | chunk :: rest -> (
          match String.split_on_char '=' chunk with
          | [ lhs; rhs ] -> to_pairs ((lhs, rhs) :: acc) rest
          | _ ->
              eval_error
                (Printf.sprintf "invalid assignment '%s' at step %d (expected x=v)" chunk idx))
    in
    match to_pairs [] chunks with
    | Error _ as err -> err
    | Ok pairs -> parse_pairs idx pairs
  in
  let split_csv_by sep (line : string) : string list =
    line |> String.split_on_char sep |> List.map String.trim
  in
  let parse_csv_lines sep lines =
    match lines with
    | [] -> Ok []
    | header :: rows ->
        let headers = split_csv_by sep header in
        if headers = [] then eval_error "empty CSV header"
        else
          let parse_row idx row =
            let cells = split_csv_by sep row in
            if List.length cells <> List.length headers then
              eval_error
                (Printf.sprintf "CSV row %d has %d values, expected %d" idx (List.length cells)
                   (List.length headers))
            else parse_pairs idx (List.combine headers cells)
          in
          let rec loop idx acc = function
            | [] -> Ok (List.rev acc)
            | row :: rest -> (
                match parse_row idx row with
                | Error _ as err -> err
                | Ok parsed -> loop (idx + 1) (parsed :: acc) rest)
          in
          loop 0 [] rows
  in
  let parse_json_object_line idx (line : string) =
    let l = String.trim line in
    let n = String.length l in
    if n < 2 || l.[0] <> '{' || l.[n - 1] <> '}' then
      eval_error (Printf.sprintf "invalid JSON object at step %d" idx)
    else
      let content = String.sub l 1 (n - 2) |> String.trim in
      let parts =
        if content = "" then []
        else content |> String.split_on_char ',' |> List.map String.trim |> List.filter (( <> ) "")
      in
      let rec parse_parts acc = function
        | [] -> Ok (List.rev acc)
        | p :: rest ->
            let colon = String.index_opt p ':' in
            (match colon with
            | None -> eval_error (Printf.sprintf "invalid JSON field '%s' at step %d" p idx)
            | Some k ->
                let key = String.sub p 0 k |> String.trim |> strip_optional_quotes in
                let value = String.sub p (k + 1) (String.length p - k - 1) |> String.trim in
                parse_parts ((key, value) :: acc) rest)
      in
      match parse_parts [] parts with
      | Error _ as err -> err
      | Ok pairs -> parse_pairs idx pairs
  in
  let rec parse_all i acc = function
    | [] -> Ok (List.rev acc)
    | line :: rest -> (
        match parse_assign_line i line with
        | Error _ as err -> err
        | Ok step -> parse_all (i + 1) (step :: acc) rest)
  in
  match lines with
  | [] -> Ok []
  | first :: _ ->
      let is_jsonl = String.length first > 0 && first.[0] = '{' in
      let no_equals = List.for_all (fun l -> not (String.contains l '=')) lines in
      let is_csv =
        not is_jsonl && no_equals
        && (String.contains first ',' || String.contains first ';' || List.length lines >= 2)
      in
      if is_jsonl then
        let rec loop i acc = function
          | [] -> Ok (List.rev acc)
          | line :: rest -> (
              match parse_json_object_line i line with
              | Error _ as err -> err
              | Ok parsed -> loop (i + 1) (parsed :: acc) rest)
        in
        loop 0 [] lines
      else if is_csv then
        let comma = String.fold_left (fun c ch -> if ch = ',' then c + 1 else c) 0 first in
        let semi = String.fold_left (fun c ch -> if ch = ';' then c + 1 else c) 0 first in
        let sep = if semi > comma then ';' else ',' in
        parse_csv_lines sep lines
      else parse_all 0 [] lines

let eval_pass ~input_file ~trace_text ~with_state ~with_locals :
    (string, Pipeline_types.error) result =
  try
    let p = Frontend.parse_file input_file in
    let n =
      match p with
      | [ n ] -> Ok n
      | [] -> eval_error "empty program"
      | nodes ->
          eval_error
            (Printf.sprintf "evaluator currently supports a single top-level node, got %d"
               (List.length nodes))
    in
    match n with
    | Error _ as err -> err
    | Ok n -> (
        match parse_trace_for_node ~n trace_text with
        | Error _ as err -> err
        | Ok steps ->
            let sem = n.semantics in
            let env : (string, eval_value) Hashtbl.t = Hashtbl.create 128 in
            List.iter
              (fun vd -> Hashtbl.replace env vd.vname (default_value_of_ty vd.vty))
              sem.sem_locals;
            List.iter
              (fun vd -> Hashtbl.replace env vd.vname (default_value_of_ty vd.vty))
              sem.sem_outputs;
            List.iter
              (fun vd -> Hashtbl.replace env vd.vname (default_value_of_ty vd.vty))
              sem.sem_inputs;
            let current_state = ref sem.sem_init_state in
            let transitions_from_state = Ast_utils.transitions_from_state_fn n in
            let lines = ref [] in
            let append_line parts = lines := (String.concat ", " parts) :: !lines in
            let run_step idx assigns =
              List.iter (fun (k, v) -> Hashtbl.replace env k v) assigns;
              let candidates = transitions_from_state !current_state in
              let rec filter_enabled acc = function
                | [] -> Ok (List.rev acc)
                | t :: rest -> (
                    match eval_guard env t.guard with
                    | Error _ as err -> err
                    | Ok true -> filter_enabled (t :: acc) rest
                    | Ok false -> filter_enabled acc rest)
              in
              match filter_enabled [] candidates with
              | Error _ as err -> err
              | Ok [] ->
                  eval_error
                    (Printf.sprintf "no enabled transition from state '%s' at step %d"
                       !current_state idx)
              | Ok [ t ] -> (
                  match eval_stmt_list env t.body with
                  | Error _ as err -> err
                  | Ok () ->
                      current_state := t.dst;
                      let inputs =
                        List.map
                          (fun vd ->
                            let v =
                              Hashtbl.find_opt env vd.vname
                              |> Option.value ~default:(default_value_of_ty vd.vty)
                            in
                            vd.vname ^ "=" ^ string_of_eval_value v)
                          sem.sem_inputs
                      in
                      let outputs =
                        List.map
                          (fun vd ->
                            let v =
                              Hashtbl.find_opt env vd.vname
                              |> Option.value ~default:(default_value_of_ty vd.vty)
                            in
                            vd.vname ^ "=" ^ string_of_eval_value v)
                          sem.sem_outputs
                      in
                      let state = if with_state then [ "state=" ^ !current_state ] else [] in
                      let locals =
                        if with_locals then
                          List.map
                            (fun vd ->
                              let v =
                                Hashtbl.find_opt env vd.vname
                                |> Option.value ~default:(default_value_of_ty vd.vty)
                              in
                              vd.vname ^ "=" ^ string_of_eval_value v)
                            sem.sem_locals
                        else []
                      in
                      append_line
                        (("step=" ^ string_of_int idx) :: state @ inputs @ outputs @ locals);
                      Ok ())
              | Ok enabled ->
                  let dsts = enabled |> List.map (fun t -> t.dst) |> String.concat ", " in
                  eval_error
                    (Printf.sprintf
                       "non-deterministic execution from state '%s' at step %d (enabled dst: %s)"
                       !current_state idx dsts)
            in
            let rec loop i = function
              | [] -> Ok ()
              | step :: rest -> (
                  match run_step i step with
                  | Error _ as err -> err
                  | Ok () -> loop (i + 1) rest)
            in
            match loop 0 steps with
            | Error _ as err -> err
            | Ok () -> Ok (String.concat "\n" (List.rev !lines)))
  with exn -> Error (Pipeline_types.Stage_error ("eval: " ^ Printexc.to_string exn))
