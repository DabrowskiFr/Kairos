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
open Support

type smt_sort = SInt | SBool

type smt_env = {
  vars : (ident, smt_sort) Hashtbl.t;
  preds : (string, unit) Hashtbl.t;
  preks : (string, unit) Hashtbl.t;
}

let z3_status_cache : (string, bool option) Hashtbl.t = Hashtbl.create 257
let z3_implies_cache : (string, bool option) Hashtbl.t = Hashtbl.create 257

let starts_with ~(prefix : string) (s : string) : bool =
  let n = String.length prefix in
  String.length s >= n && String.sub s 0 n = prefix

let rec sanitize_ident (s : string) : string =
  let buf = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> Buffer.add_char buf c
      | _ -> Buffer.add_char buf '_')
    s;
  let out = Buffer.contents buf in
  if out = "" then "__kairos"
  else
    match out.[0] with
    | '0' .. '9' -> "__" ^ out
    | _ -> out

let string_of_sort = function SInt -> "Int" | SBool -> "Bool"

let rec infer_iexpr_sort (vars : (ident, smt_sort) Hashtbl.t) (e : iexpr) : smt_sort option =
  let unify_var v s =
    match Hashtbl.find_opt vars v with
    | None ->
        Hashtbl.add vars v s;
        Some s
    | Some s' -> Some s'
  in
  match e.iexpr with
  | ILitInt _ -> Some SInt
  | ILitBool _ -> Some SBool
  | IVar v -> Hashtbl.find_opt vars v
  | IUn (Neg, a) ->
      let _ = infer_iexpr_sort vars a in
      Some SInt
  | IUn (Not, a) ->
      let _ = infer_iexpr_sort vars a in
      Some SBool
  | IBin (Add, a, b) | IBin (Sub, a, b) | IBin (Mul, a, b) | IBin (Div, a, b) ->
      let _ = infer_iexpr_sort vars a in
      let _ = infer_iexpr_sort vars b in
      Some SInt
  | IBin (And, a, b) | IBin (Or, a, b) ->
      let _ = infer_iexpr_sort vars a in
      let _ = infer_iexpr_sort vars b in
      Some SBool
  | IBin (Lt, a, b) | IBin (Le, a, b) | IBin (Gt, a, b) | IBin (Ge, a, b) ->
      let _ = infer_iexpr_sort vars a in
      let _ = infer_iexpr_sort vars b in
      Some SBool
  | IBin (Eq, a, b) | IBin (Neq, a, b) -> begin
      let sa = infer_iexpr_sort vars a in
      let sb = infer_iexpr_sort vars b in
      let operand_sort =
        match (sa, sb) with Some s, _ | _, Some s -> s | None, None -> SInt
      in
      (match a.iexpr with IVar v -> ignore (unify_var v operand_sort) | _ -> ());
      (match b.iexpr with IVar v -> ignore (unify_var v operand_sort) | _ -> ());
      Some SBool
    end
  | IPar a -> infer_iexpr_sort vars a

let infer_hexpr_sort vars = function
  | HNow e | HPreK (e, _) -> infer_iexpr_sort vars e

let infer_formula_sorts (f : fo) : (ident, smt_sort) Hashtbl.t =
  let vars = Hashtbl.create 32 in
  let rec go = function
    | FTrue | FFalse -> ()
    | FRel (h1, r, h2) -> begin
        match r with
        | RLt | RLe | RGt | RGe ->
            let _ = infer_hexpr_sort vars h1 in
            let _ = infer_hexpr_sort vars h2 in
            ()
        | REq | RNeq ->
            let s1 = infer_hexpr_sort vars h1 in
            let s2 = infer_hexpr_sort vars h2 in
            let s =
              match (s1, s2) with Some s, _ | _, Some s -> s | None, None -> SInt
            in
            begin
              match h1 with HNow { iexpr = IVar v; _ } | HPreK ({ iexpr = IVar v; _ }, _) ->
                Hashtbl.replace vars v s
              | _ -> ()
            end;
            begin
              match h2 with HNow { iexpr = IVar v; _ } | HPreK ({ iexpr = IVar v; _ }, _) ->
                Hashtbl.replace vars v s
              | _ -> ()
            end
      end
    | FPred (_, hs) -> List.iter (fun h -> ignore (infer_hexpr_sort vars h)) hs
    | FNot a -> go a
    | FAnd (a, b) | FOr (a, b) | FImp (a, b) ->
        go a;
        go b
  in
  go f;
  vars

let make_env (f : fo) : smt_env =
  { vars = infer_formula_sorts f; preds = Hashtbl.create 16; preks = Hashtbl.create 16 }

let smt_var_name (v : ident) : string = "__v_" ^ sanitize_ident v
let smt_pred_name (id : ident) (arity : int) : string = "__p_" ^ sanitize_ident id ^ "_" ^ string_of_int arity

let smt_prek_name (k : int) (sort : smt_sort) : string =
  "__pre_" ^ string_of_int k ^ "_" ^ String.lowercase_ascii (string_of_sort sort)

let rec smt_of_iexpr (env : smt_env) (e : iexpr) : string * smt_sort =
  match e.iexpr with
  | ILitInt i -> (string_of_int i, SInt)
  | ILitBool true -> ("true", SBool)
  | ILitBool false -> ("false", SBool)
  | IVar v ->
      let sort = Hashtbl.find_opt env.vars v |> Option.value ~default:SInt in
      Hashtbl.replace env.vars v sort;
      (smt_var_name v, sort)
  | IUn (Neg, a) ->
      let sa, _ = smt_of_iexpr env a in
      ("(- " ^ sa ^ ")", SInt)
  | IUn (Not, a) ->
      let sa, _ = smt_of_iexpr env a in
      ("(not " ^ sa ^ ")", SBool)
  | IBin (Add, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(+ " ^ sa ^ " " ^ sb ^ ")", SInt)
  | IBin (Sub, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(- " ^ sa ^ " " ^ sb ^ ")", SInt)
  | IBin (Mul, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(* " ^ sa ^ " " ^ sb ^ ")", SInt)
  | IBin (Div, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(div " ^ sa ^ " " ^ sb ^ ")", SInt)
  | IBin (And, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(and " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Or, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(or " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Eq, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(= " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Neq, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(not (= " ^ sa ^ " " ^ sb ^ "))", SBool)
  | IBin (Lt, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(< " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Le, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(<= " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Gt, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(> " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Ge, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(>= " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IPar a -> smt_of_iexpr env a

let smt_of_hexpr (env : smt_env) = function
  | HNow e -> smt_of_iexpr env e
  | HPreK (e, k) ->
      let se, sort = smt_of_iexpr env e in
      let fname = smt_prek_name k sort in
      Hashtbl.replace env.preks fname ();
      ("(" ^ fname ^ " " ^ se ^ ")", sort)

let rec smt_of_fo (env : smt_env) = function
  | FTrue -> "true"
  | FFalse -> "false"
  | FRel (h1, REq, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(= " ^ s1 ^ " " ^ s2 ^ ")"
  | FRel (h1, RNeq, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(not (= " ^ s1 ^ " " ^ s2 ^ "))"
  | FRel (h1, RLt, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(< " ^ s1 ^ " " ^ s2 ^ ")"
  | FRel (h1, RLe, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(<= " ^ s1 ^ " " ^ s2 ^ ")"
  | FRel (h1, RGt, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(> " ^ s1 ^ " " ^ s2 ^ ")"
  | FRel (h1, RGe, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(>= " ^ s1 ^ " " ^ s2 ^ ")"
  | FPred (id, hs) ->
      let args = List.map (smt_of_hexpr env) hs in
      let name = smt_pred_name id (List.length hs) in
      Hashtbl.replace env.preds name ();
      "(" ^ name ^ (if args = [] then "" else " " ^ String.concat " " (List.map fst args)) ^ ")"
  | FNot a -> "(not " ^ smt_of_fo env a ^ ")"
  | FAnd (a, b) -> "(and " ^ smt_of_fo env a ^ " " ^ smt_of_fo env b ^ ")"
  | FOr (a, b) -> "(or " ^ smt_of_fo env a ^ " " ^ smt_of_fo env b ^ ")"
  | FImp (a, b) -> "(=> " ^ smt_of_fo env a ^ " " ^ smt_of_fo env b ^ ")"

let declarations_of_env (env : smt_env) : string list =
  let decls = ref [] in
  Hashtbl.iter
    (fun v sort ->
      decls := Printf.sprintf "(declare-fun %s () %s)" (smt_var_name v) (string_of_sort sort) :: !decls)
    env.vars;
  Hashtbl.iter
    (fun name () ->
      let arity =
        try
          let i = String.rindex name '_' in
          int_of_string (String.sub name (i + 1) (String.length name - i - 1))
        with _ -> 0
      in
      let args = List.init arity (fun _ -> "Int") |> String.concat " " in
      let args = if args = "" then "" else args ^ " " in
      decls := Printf.sprintf "(declare-fun %s (%s) Bool)" name args :: !decls)
    env.preds;
  Hashtbl.iter
    (fun name () ->
      let sort =
        if String.ends_with ~suffix:"_bool" name then "Bool"
        else "Int"
      in
      decls := Printf.sprintf "(declare-fun %s (%s) %s)" name sort sort :: !decls)
    env.preks;
  List.rev !decls

let read_all (ic : in_channel) : string =
  let buf = Buffer.create 1024 in
  (try
     while true do
       Buffer.add_channel buf ic 1024
     done
   with End_of_file -> ());
  Buffer.contents buf

let z3_command () : string =
  let env_path =
    match Sys.getenv_opt "KAIROS_Z3" with Some p when Sys.file_exists p -> Some p | _ -> None
  in
  match env_path with
  | Some p -> Filename.quote p ^ " -in -smt2"
  | None ->
      let candidates =
        [
          "/opt/homebrew/bin/z3";
          "/usr/local/bin/z3";
          "/usr/bin/z3";
          (match Sys.getenv_opt "OPAM_SWITCH_PREFIX" with
          | Some p -> Filename.concat p "bin/z3"
          | None -> "");
        ]
        |> List.filter (fun p -> p <> "" && Sys.file_exists p)
      in
      (match candidates with
      | p :: _ -> Filename.quote p ^ " -in -smt2"
      | [] ->
          let opam =
            [ "/opt/homebrew/bin/opam"; "/usr/local/bin/opam"; "/usr/bin/opam" ]
            |> List.find_opt Sys.file_exists
          in
          match opam with
          | Some p -> Filename.quote p ^ " exec -- z3 -in -smt2"
          | None -> "")

let run_z3_query (query_key : string) (script : string) : bool option =
  match Hashtbl.find_opt z3_status_cache query_key with
  | Some cached -> cached
  | None ->
      let cmd = z3_command () in
      if cmd = "" then None
      else
        let ic, oc, ec = Unix.open_process_full cmd (Unix.environment ()) in
        output_string oc script;
        close_out oc;
        let stdout = read_all ic |> String.trim in
        let _stderr = read_all ec in
        let _ = Unix.close_process_full (ic, oc, ec) in
        let result =
          if starts_with ~prefix:"unsat" stdout then Some true
          else if starts_with ~prefix:"sat" stdout then Some false
          else None
        in
        Hashtbl.replace z3_status_cache query_key result;
        result

let prove_formula (f : fo) : bool option =
  let env = make_env f in
  let body = smt_of_fo env f in
  let script =
    String.concat "\n"
      (["(set-logic ALL)"] @ declarations_of_env env @ [ "(assert (not " ^ body ^ "))"; "(check-sat)" ])
    ^ "\n"
  in
  run_z3_query ("valid:" ^ string_of_fo f) script

let unsat_formula (f : fo) : bool option =
  let env = make_env f in
  let body = smt_of_fo env f in
  let script =
    String.concat "\n" (["(set-logic ALL)"] @ declarations_of_env env @ [ "(assert " ^ body ^ ")"; "(check-sat)" ])
    ^ "\n"
  in
  match run_z3_query ("unsat:" ^ string_of_fo f) script with
  | Some true -> Some false
  | Some false -> Some true
  | None -> None

let implies_formula (a : fo) (b : fo) : bool option =
  let key = string_of_fo a ^ " => " ^ string_of_fo b in
  match Hashtbl.find_opt z3_implies_cache key with
  | Some cached -> cached
  | None ->
      let f = FImp (a, b) in
      let result = prove_formula f in
      Hashtbl.replace z3_implies_cache key result;
      result

let rec flatten_and acc = function
  | FAnd (a, b) -> flatten_and (flatten_and acc a) b
  | x -> x :: acc

let rec flatten_or acc = function
  | FOr (a, b) -> flatten_or (flatten_or acc a) b
  | x -> x :: acc

let rebuild_and = function
  | [] -> FTrue
  | [ x ] -> x
  | x :: xs -> List.fold_left (fun acc y -> FAnd (acc, y)) x xs

let rebuild_or = function
  | [] -> FFalse
  | [ x ] -> x
  | x :: xs -> List.fold_left (fun acc y -> FOr (acc, y)) x xs

let syntactic_rel_simplify = function
  | FRel (h1, REq, h2) when h1 = h2 -> Some FTrue
  | FRel (h1, RNeq, h2) when h1 = h2 -> Some FFalse
  | _ -> None

let simplify_and_parts (parts : fo list) : fo =
  let rec loop acc = function
    | [] -> rebuild_and (List.rev acc)
    | x :: xs when x = FTrue -> loop acc xs
    | x :: _ when x = FFalse -> FFalse
    | x :: xs when List.exists (( = ) x) acc -> loop acc xs
    | x :: xs ->
        if List.exists (fun y -> implies_formula y x = Some true) acc then loop acc xs
        else
          let acc = List.filter (fun y -> implies_formula x y <> Some true) acc in
          loop (x :: acc) xs
  in
  loop [] parts

let simplify_or_parts (parts : fo list) : fo =
  let rec loop acc = function
    | [] -> rebuild_or (List.rev acc)
    | x :: xs when x = FFalse -> loop acc xs
    | x :: _ when x = FTrue -> FTrue
    | x :: xs when List.exists (( = ) x) acc -> loop acc xs
    | x :: xs ->
        if List.exists (fun y -> implies_formula x y = Some true) acc then loop acc xs
        else
          let acc = List.filter (fun y -> implies_formula y x <> Some true) acc in
          loop (x :: acc) xs
  in
  loop [] parts

let solver_enabled () =
  match Sys.getenv_opt "KAIROS_FO_SIMPLIFIER" with
  | Some "off" -> false
  | _ -> z3_command () <> ""

let rec simplify_fo (f : fo) : fo =
  let rec go = function
    | FTrue | FFalse | FPred _ as f -> f
    | FRel _ as f -> begin match syntactic_rel_simplify f with Some g -> g | None -> f end
    | FNot a -> begin
        match go a with
        | FTrue -> FFalse
        | FFalse -> FTrue
        | FNot b -> b
        | a' ->
            let f' = FNot a' in
            if solver_enabled () then
              match (prove_formula f', unsat_formula f') with
              | Some true, _ -> FTrue
              | _, Some true -> FFalse
              | _ -> f'
            else f'
      end
    | FAnd _ as f ->
        let parts = flatten_and [] f |> List.map go in
        let f' = simplify_and_parts parts in
        if solver_enabled () then
          match (prove_formula f', unsat_formula f') with
          | Some true, _ -> FTrue
          | _, Some true -> FFalse
          | _ -> f'
        else f'
    | FOr _ as f ->
        let parts = flatten_or [] f |> List.map go in
        let f' = simplify_or_parts parts in
        if solver_enabled () then
          match (prove_formula f', unsat_formula f') with
          | Some true, _ -> FTrue
          | _, Some true -> FFalse
          | _ -> f'
        else f'
    | FImp (a, b) ->
        let a = go a in
        let b = go b in
        let f' =
          match (a, b) with
          | FFalse, _ | _, FTrue -> FTrue
          | FTrue, x -> x
          | x, FFalse -> go (FNot x)
          | _ when a = b -> FTrue
          | _ ->
              if solver_enabled () && implies_formula a b = Some true then FTrue else FImp (a, b)
        in
        if solver_enabled () then
          match (prove_formula f', unsat_formula f') with
          | Some true, _ -> FTrue
          | _, Some true -> FFalse
          | _ -> f'
        else f'
  in
  go f
