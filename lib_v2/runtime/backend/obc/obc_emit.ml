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
open Ast_builders
open Support

let indent_str (n : int) : string = String.make (2 * n) ' '

let starts_with (s : string) (prefix : string) : bool =
  let ls = String.length s in
  let lp = String.length prefix in
  ls >= lp && String.sub s 0 lp = prefix

let is_mon_ctor (s : string) : bool =
  let len = String.length s in
  len >= 4
  && String.sub s 0 3 = "Aut"
  && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub s 3 (len - 3))

let is_generated_ident (id : string) : bool =
  starts_with id "__aut_state" || starts_with id "__aut_" || is_mon_ctor id

type gen_tag =
  | MonitorAtom
  | MonitorState
  | CompatInvariant
  | BadState
  | MonitorPre
  | MonitorPost
  | PostForNextPre

let tag_label = function
  | MonitorAtom -> "automata atom definition"
  | MonitorState -> "automata state"
  | CompatInvariant -> "automata/program compatibility"
  | BadState -> "no bad state"
  | MonitorPre -> "automata pre-condition"
  | MonitorPost -> "automata post-condition"
  | PostForNextPre -> "post -> next pre"

let rec iexpr_mentions_generated (e : iexpr) : bool =
  match e.iexpr with
  | ILitInt _ | ILitBool _ -> false
  | IVar id -> is_generated_ident id
  | IPar e -> iexpr_mentions_generated e
  | IUn (_, e) -> iexpr_mentions_generated e
  | IBin (_, a, b) -> iexpr_mentions_generated a || iexpr_mentions_generated b

let rec iexpr_has_tag (tag : gen_tag) (e : iexpr) : bool =
  match e.iexpr with
  | ILitInt _ | ILitBool _ -> false
  | IVar id -> begin
      match tag with
      | MonitorAtom -> false
      | MonitorState -> id = "__aut_state" || is_mon_ctor id
      | CompatInvariant | BadState | MonitorPre | MonitorPost | PostForNextPre -> false
    end
  | IPar e -> iexpr_has_tag tag e
  | IUn (_, e) -> iexpr_has_tag tag e
  | IBin (_, a, b) -> iexpr_has_tag tag a || iexpr_has_tag tag b

let rec hexpr_mentions_generated (h : hexpr) : bool =
  match h with HNow e -> iexpr_mentions_generated e | HPreK (e, _) -> iexpr_mentions_generated e

let rec hexpr_has_tag (tag : gen_tag) (h : hexpr) : bool =
  match h with HNow e -> iexpr_has_tag tag e | HPreK (e, _) -> iexpr_has_tag tag e

let rec fo_mentions_generated (f : fo) : bool =
  match f with
  | FTrue | FFalse -> false
  | FRel (h1, _, h2) -> hexpr_mentions_generated h1 || hexpr_mentions_generated h2
  | FPred (_, hs) -> List.exists hexpr_mentions_generated hs
  | FNot a -> fo_mentions_generated a
  | FAnd (a, b) | FOr (a, b) | FImp (a, b) -> fo_mentions_generated a || fo_mentions_generated b

let rec fo_has_tag (tag : gen_tag) (f : fo) : bool =
  match f with
  | FTrue | FFalse -> false
  | FRel (h1, _, h2) -> hexpr_has_tag tag h1 || hexpr_has_tag tag h2
  | FPred (_, hs) -> List.exists (hexpr_has_tag tag) hs
  | FNot a -> fo_has_tag tag a
  | FAnd (a, b) | FOr (a, b) | FImp (a, b) -> fo_has_tag tag a || fo_has_tag tag b

let is_mon_state_var = function "__aut_state" -> true | s -> is_mon_ctor s

let rec iexpr_only_mon_state = function
  | e -> (
      match e.iexpr with
      | ILitInt _ | ILitBool _ -> true
      | IVar id -> is_mon_state_var id
      | IPar inner -> iexpr_only_mon_state inner
      | IUn (_, inner) -> iexpr_only_mon_state inner
      | IBin (_, a, b) -> iexpr_only_mon_state a && iexpr_only_mon_state b)

let rec hexpr_only_mon_state = function
  | HNow e -> iexpr_only_mon_state e
  | HPreK (e, _) -> iexpr_only_mon_state e

let rec fo_only_mon_state = function
  | FTrue | FFalse -> true
  | FRel (h1, _, h2) -> hexpr_only_mon_state h1 && hexpr_only_mon_state h2
  | FPred (_, hs) -> List.for_all hexpr_only_mon_state hs
  | FNot a -> fo_only_mon_state a
  | FAnd (a, b) | FOr (a, b) | FImp (a, b) -> fo_only_mon_state a && fo_only_mon_state b

let is_mon_state_eq = function
  | FRel (HNow a, REq, HNow b) -> begin
      match (as_var a, as_var b) with
      | Some va, Some vb -> is_mon_state_var va && is_mon_state_var vb
      | _ -> false
    end
  | _ -> false

let is_bad_state_formula = function
  | FRel (HNow a, RNeq, HNow b) -> begin
      match (as_var a, as_var b) with
      | Some va, Some vb -> is_mon_state_var va && is_mon_state_var vb
      | _ -> false
    end
  | _ -> false

let is_monitor_implication = function FImp (cond, _body) -> is_mon_state_eq cond | _ -> false
let comment_line (indent : int) (msg : string) : string = indent_str indent ^ "(* " ^ msg ^ " *)"
let comment_for_tag indent tag = comment_line indent ("generated: " ^ tag_label tag)

let comment_for_tags indent tags =
  let tags = List.sort_uniq compare tags in
  let explicit_tags =
    List.filter (function MonitorAtom | MonitorState -> true | _ -> false) tags
  in
  List.map (comment_for_tag indent) explicit_tags

let tags_for_ident (id : string) : gen_tag list =
  let tags = ref [] in
  if id = "__aut_state" || is_mon_ctor id then tags := MonitorState :: !tags;
  !tags

let tags_for_iexpr (e : iexpr) : gen_tag list =
  let tags = ref [] in
  if iexpr_has_tag MonitorState e then tags := MonitorState :: !tags;
  !tags

let tags_for_fo (f : fo) : gen_tag list =
  let tags = ref [] in
  if fo_has_tag MonitorState f then tags := MonitorState :: !tags;
  if is_bad_state_formula f then tags := BadState :: !tags;
  if (not (is_bad_state_formula f)) && fo_only_mon_state f then tags := CompatInvariant :: !tags;
  !tags

let tags_for_fo_with_context ~(is_require : bool) (f : fo) : gen_tag list =
  let tags = tags_for_fo f in
  if is_monitor_implication f then if is_require then MonitorPre :: tags else MonitorPost :: tags
  else tags

let primary_tag_for_fo ~(is_require : bool) (f : fo) : gen_tag option =
  let tags = tags_for_fo_with_context ~is_require f in
  if is_require && List.mem MonitorPre tags then Some CompatInvariant
  else
    let priority =
      [
        CompatInvariant;
        BadState;
        MonitorPre;
        MonitorPost;
        PostForNextPre;
        MonitorAtom;
        MonitorState;
      ]
    in
    List.find_opt (fun t -> List.mem t tags) priority

let add_semicolon (lines : string list) : string list =
  match List.rev lines with [] -> [] | last :: rest_rev -> List.rev ((last ^ ";") :: rest_rev)

let rec stmt_lines ?(allow_empty = true) ?(with_comments = true) (indent : int) (stmts : stmt list)
    : string list =
  match stmts with
  | [] -> if allow_empty then [] else [ indent_str indent ^ "skip" ]
  | _ -> List.concat_map (fun s -> add_semicolon (stmt_one_lines ~with_comments indent s)) stmts

and stmt_one_lines ?(with_comments = true) (indent : int) (s : stmt) : string list =
  let tags =
    match s.stmt with
    | SAssign (id, e) -> tags_for_ident id @ tags_for_iexpr e
    | SIf (c, _, _) -> tags_for_iexpr c
    | SMatch (e, _, _) -> tags_for_iexpr e
    | SCall _ | SSkip -> []
  in
  let prefix = if with_comments then comment_for_tags indent tags else [] in
  match s.stmt with
  | SAssign (id, e) -> prefix @ [ indent_str indent ^ id ^ " := " ^ string_of_iexpr e ]
  | SSkip -> prefix @ [ indent_str indent ^ "skip" ]
  | SCall (inst, args, outs) ->
      let args_s = String.concat ", " (List.map string_of_iexpr args) in
      let outs_s = String.concat ", " outs in
      prefix @ [ indent_str indent ^ "call " ^ inst ^ "(" ^ args_s ^ ") returns (" ^ outs_s ^ ")" ]
  | SIf (cond, tbr, fbr) ->
      prefix
      @ [ indent_str indent ^ "if " ^ string_of_iexpr cond ^ " then" ]
      @ stmt_lines ~allow_empty:false ~with_comments (indent + 1) tbr
      @ [ indent_str indent ^ "else" ]
      @ stmt_lines ~allow_empty:false ~with_comments (indent + 1) fbr
      @ [ indent_str indent ^ "end" ]
  | SMatch (e, branches, def) ->
      prefix
      @ [ indent_str indent ^ "match " ^ string_of_iexpr e ^ " with" ]
      @ List.concat_map
          (fun (ctor, body) ->
            [ indent_str indent ^ "| " ^ ctor ^ " ->" ]
            @ stmt_lines ~allow_empty:false ~with_comments (indent + 1) body)
          branches
      @ (if def = [] then []
         else
           [ indent_str indent ^ "| _ ->" ]
           @ stmt_lines ~allow_empty:false ~with_comments (indent + 1) def)
      @ [ indent_str indent ^ "end" ]

let vdecl_line (v : vdecl) : string =
  v.vname ^ ": "
  ^ match v.vty with TInt -> "int" | TBool -> "bool" | TReal -> "real" | TCustom s -> s

let local_comment (name : ident) : string option =
  let has_prefix p =
    String.length name >= String.length p && String.sub name 0 (String.length p) = p
  in
  if name = "__aut_state" then Some "automata state"
  else if has_prefix "__pre_k" then Some "k-step history"
  else Some "user local"

let params_of_vdecls (vs : vdecl list) : string = String.concat ", " (List.map vdecl_line vs)

let replace_all ~sub ~by s =
  if sub = "" then s
  else
    let sub_len = String.length sub in
    let len = String.length s in
    let b = Buffer.create len in
    let rec loop i =
      if i >= len then ()
      else if i + sub_len <= len && String.sub s i sub_len = sub then (
        Buffer.add_string b by;
        loop (i + sub_len))
      else (
        Buffer.add_char b s.[i];
        loop (i + 1))
    in
    loop 0;
    Buffer.contents b

let prettify_pre_old ~init_for_var:_ ~vars:_ s = s

let pre_k_var_map (n : node) : (hexpr * ident) list =
  let pre_k_map = Collect.build_pre_k_infos n in
  List.filter_map
    (fun (h, info) ->
      match info.Support.names with
      | [] -> None
      | names -> Some (h, List.nth names (List.length names - 1)))
    pre_k_map

let rec replace_pre_k_hexpr ~(map : (hexpr * ident) list) (h : hexpr) : hexpr =
  match h with
  | HPreK _ as h -> begin
      match List.assoc_opt h map with Some name -> HNow (mk_var name) | None -> h
    end
  | HNow _ -> h

let rec replace_pre_k_fo ~(map : (hexpr * ident) list) (f : fo) : fo =
  match f with
  | FTrue | FFalse -> f
  | FNot a -> FNot (replace_pre_k_fo ~map a)
  | FAnd (a, b) -> FAnd (replace_pre_k_fo ~map a, replace_pre_k_fo ~map b)
  | FOr (a, b) -> FOr (replace_pre_k_fo ~map a, replace_pre_k_fo ~map b)
  | FImp (a, b) -> FImp (replace_pre_k_fo ~map a, replace_pre_k_fo ~map b)
  | FRel (h1, r, h2) -> FRel (replace_pre_k_hexpr ~map h1, r, replace_pre_k_hexpr ~map h2)
  | FPred (id, hs) -> FPred (id, List.map (replace_pre_k_hexpr ~map) hs)

let rec replace_pre_k_ltl ~(map : (hexpr * ident) list) (f : fo_ltl) : fo_ltl =
  match f with
  | LTrue -> LTrue
  | LFalse -> LFalse
  | LAtom a -> LAtom (replace_pre_k_fo ~map a)
  | LNot a -> LNot (replace_pre_k_ltl ~map a)
  | LX a -> LX (replace_pre_k_ltl ~map a)
  | LG a -> LG (replace_pre_k_ltl ~map a)
  | LW (a, b) -> LW (replace_pre_k_ltl ~map a, replace_pre_k_ltl ~map b)
  | LAnd (a, b) -> LAnd (replace_pre_k_ltl ~map a, replace_pre_k_ltl ~map b)
  | LOr (a, b) -> LOr (replace_pre_k_ltl ~map a, replace_pre_k_ltl ~map b)
  | LImp (a, b) -> LImp (replace_pre_k_ltl ~map a, replace_pre_k_ltl ~map b)

let replace_pre_k_invariant_user ~(map : (hexpr * ident) list) (inv : invariant_user) :
    invariant_user =
  { inv with inv_expr = replace_pre_k_hexpr ~map inv.inv_expr }

let replace_pre_k_invariant_state_rel ~(map : (hexpr * ident) list) (inv : invariant_state_rel) :
    invariant_state_rel =
  { inv with formula = replace_pre_k_fo ~map inv.formula }

let replace_pre_k_coherency_goal ~(map : (hexpr * ident) list) (f : fo_o) : fo_o =
  Ast_provenance.map_with_origin (replace_pre_k_fo ~map) f

let replace_pre_k_transition ~(map : (hexpr * ident) list) (t : transition) : transition =
  {
    t with
    requires = List.map (Ast_provenance.map_with_origin (replace_pre_k_fo ~map)) t.requires;
    ensures = List.map (Ast_provenance.map_with_origin (replace_pre_k_fo ~map)) t.ensures;
  }

let replace_pre_k_node (n : node) : node =
  let map = pre_k_var_map n in
  let spec = Ast.specification_of_node n in
  let n =
    {
      n with
      assumes = List.map (replace_pre_k_ltl ~map) spec.spec_assumes;
      guarantees = List.map (replace_pre_k_ltl ~map) spec.spec_guarantees;
      trans = List.map (replace_pre_k_transition ~map) n.trans;
    }
  in
  {
    n with
    attrs =
      {
        n.attrs with
        invariants_user = List.map (replace_pre_k_invariant_user ~map) n.attrs.invariants_user;
        invariants_state_rel =
          List.map (replace_pre_k_invariant_state_rel ~map) spec.spec_invariants_state_rel;
        coherency_goals = List.map (replace_pre_k_coherency_goal ~map) n.attrs.coherency_goals;
      };
  }

let contract_lines (indent : int) (assumes : fo_ltl list) (guarantees : fo_ltl list)
    ~(invariants_user : invariant_user list) ~(invariants_state_rel : invariant_state_rel list)
    ~(init_for_var : ident -> iexpr) ~(vars : ident list) : string list =
  let assume_lines =
    List.map (fun f -> indent_str indent ^ "requires " ^ string_of_ltl f ^ ";") assumes
  in
  let guarantee_lines =
    List.map (fun f -> indent_str indent ^ "ensures " ^ string_of_ltl f ^ ";") guarantees
  in
  let inv_lines =
    let add_with_prefix (acc, last_prefix) prefix line =
      if prefix = [] || prefix = last_prefix then (acc @ [ line ], last_prefix)
      else (acc @ prefix @ [ line ], prefix)
    in
    let add_user acc last_prefix inv =
      let tags =
        tags_for_ident inv.inv_id
        @ (if hexpr_has_tag MonitorAtom inv.inv_expr then [ MonitorAtom ] else [])
        @ if hexpr_has_tag MonitorState inv.inv_expr then [ MonitorState ] else []
      in
      let prefix = comment_for_tags indent tags in
      let line =
        indent_str indent ^ "(* invariant " ^ inv.inv_id ^ " = " ^ string_of_hexpr inv.inv_expr
        ^ " *)"
      in
      let line = prettify_pre_old ~init_for_var ~vars line in
      add_with_prefix (acc, last_prefix) prefix line
    in
    let add_state_rel acc last_prefix inv =
      let op = if inv.is_eq then "=" else "!=" in
      let tags = tags_for_fo inv.formula in
      let prefix = comment_for_tags indent tags in
      let line =
        indent_str indent ^ "(* invariant state " ^ op ^ " " ^ inv.state ^ " -> "
        ^ string_of_fo inv.formula ^ " *)"
      in
      let line = prettify_pre_old ~init_for_var ~vars line in
      add_with_prefix (acc, last_prefix) prefix line
    in
    let acc, last_prefix =
      List.fold_left
        (fun (acc, last_prefix) inv -> add_user acc last_prefix inv)
        ([], []) invariants_user
    in
    let acc, _ =
      List.fold_left
        (fun (acc, last_prefix) inv -> add_state_rel acc last_prefix inv)
        (acc, last_prefix) invariants_state_rel
    in
    acc
  in
  assume_lines @ guarantee_lines @ inv_lines

type label_counters = { mutable req : int; mutable ens : int }

let coherency_goal_lines (indent : int) ~(goals : fo_o list) ~(init_for_var : ident -> iexpr)
    ~(vars : ident list) : string list =
  if goals = [] then []
  else
    let is_init_goal = function FImp (FTrue, _) -> true | _ -> false in
    let compare_goal a b = compare (string_of_fo a.value) (string_of_fo b.value) in
    let init_goals, transition_goals = List.partition (fun f -> is_init_goal f.value) goals in
    let emit_group acc title group next_id =
      if group = [] then (acc, next_id)
      else
        let group = List.sort compare_goal group in
        let lines, next_id =
          List.fold_left
            (fun (acc, id) f ->
              let line = indent_str indent ^ "goal " ^ string_of_fo f.value ^ ";" in
              let line = prettify_pre_old ~init_for_var ~vars line in
              (acc @ [ line ^ "  (* C" ^ string_of_int id ^ " *)" ], id + 1))
            ([], next_id) group
        in
        (acc @ [ comment_line indent title ] @ lines, next_id)
    in
    let acc, next_id = emit_group [] "-- coherency goals (init) --" init_goals 1 in
    let acc, _ = emit_group acc "-- coherency goals (transitions) --" transition_goals next_id in
    acc

let is_contract_coherency (f : fo) : bool = match f with FImp _ -> true | _ -> false

let source_of_fo ~(is_require : bool) (f : fo_o) : string =
  match f.origin with
  | Some UserContract -> "user"
  | Some Coherency -> "user contracts coherency"
  | Some Compatibility -> "automata/program compatibility"
  | Some AssumeAutomaton -> "assumption automaton"
  | Some Instrumentation -> if is_require then "automata pre-condition" else "automata post-condition"
  | Some Internal -> "internal"
  | None -> (
      match primary_tag_for_fo ~is_require f.value with
      | Some t -> tag_label t
      | None ->
          if (not is_require) && is_contract_coherency f.value then "user contracts coherency"
          else "user")

let source_order (s : string) : int =
  match s with
  | "user" -> 0
  | "user contracts coherency" -> 1
  | "automata/program compatibility" -> 2
  | "assumption automaton" -> 3
  | "no bad state" -> 3
  | "automata pre-condition" -> 4
  | "automata post-condition" -> 5
  | "internal fold link" -> 6
  | "automata atom definition" -> 7
  | "automata state" -> 8
  | _ -> 9

type bool_lit = Pos of string * int | Neg of string * int

let eq_var_int (f : fo) : (string * int) option =
  match f with
  | FRel (HNow a, REq, HNow b) -> begin
      match (a.iexpr, b.iexpr) with
      | IVar v, ILitInt c -> Some (v, c)
      | ILitInt c, IVar v -> Some (v, c)
      | _ -> None
    end
  | _ -> None

let rec and_terms (f : fo) : fo list = match f with FAnd (a, b) -> and_terms a @ and_terms b | _ -> [ f ]
let rec or_terms (f : fo) : fo list = match f with FOr (a, b) -> or_terms a @ or_terms b | _ -> [ f ]

let bool_lit_of_fo (f : fo) : bool_lit option =
  match f with
  | FNot inner -> Option.map (fun (v, c) -> Neg (v, c)) (eq_var_int inner)
  | _ -> Option.map (fun (v, c) -> Pos (v, c)) (eq_var_int f)

let collect_some (xs : 'a option list) : 'a list option =
  List.fold_right
    (fun x acc -> Option.bind x (fun v -> Option.map (fun r -> v :: r) acc))
    xs (Some [])

let decode_bool_choice (lits : bool_lit list) : (string * int) list option =
  let tbl = Hashtbl.create 16 in
  let add v c is_pos =
    let v0, n0, v1, n1 =
      Hashtbl.find_opt tbl v |> Option.value ~default:(false, false, false, false)
    in
    let next =
      match (c, is_pos) with
      | 0, true -> (true, n0, v1, n1)
      | 0, false -> (v0, true, v1, n1)
      | 1, true -> (v0, n0, true, n1)
      | 1, false -> (v0, n0, v1, true)
      | _ -> (v0, n0, v1, n1)
    in
    Hashtbl.replace tbl v next
  in
  List.iter
    (function
      | Pos (v, c) when c = 0 || c = 1 -> add v c true
      | Neg (v, c) when c = 0 || c = 1 -> add v c false
      | _ -> ())
    lits;
  let bad =
    List.exists
      (function
        | Pos (_, c) | Neg (_, c) -> c <> 0 && c <> 1)
      lits
  in
  if bad then None
  else
    let out = ref [] in
    let ok = ref true in
    Hashtbl.iter
      (fun v (v0, n0, v1, n1) ->
        if v0 && n1 && not (v1 || n0) then out := (v, 0) :: !out
        else if v1 && n0 && not (v0 || n1) then out := (v, 1) :: !out
        else ok := false)
      tbl;
    if !ok then Some !out else None

let simplify_assume_dnf_bool_domain (f : fo) : fo =
  let terms = or_terms f in
  let decoded =
    List.map
      (fun t ->
        match and_terms t |> List.map bool_lit_of_fo |> collect_some with
        | None -> None
        | Some lits -> decode_bool_choice lits)
      terms
  in
  match collect_some decoded with
  | None -> f
  | Some choices -> begin
      match choices with
      | [] -> f
      | first :: _ ->
          let vars = List.map fst first |> List.sort_uniq String.compare in
          let per_term_same_vars =
            List.for_all
              (fun ch -> List.sort_uniq String.compare (List.map fst ch) = vars)
              choices
          in
          if not per_term_same_vars then f
          else
            let tbl = Hashtbl.create 32 in
            let key_of_choice ch =
              ch
              |> List.sort (fun (a, _) (b, _) -> String.compare a b)
              |> List.map (fun (_v, c) -> string_of_int c)
              |> String.concat ","
            in
            List.iter (fun ch -> Hashtbl.replace tbl (key_of_choice ch) true) choices;
            let expected = 1 lsl List.length vars in
            if Hashtbl.length tbl <> expected then f
            else
              let var_formula v =
                FOr
                  ( FRel (HNow (mk_var v), REq, HNow (mk_int 0)),
                    FRel (HNow (mk_var v), REq, HNow (mk_int 1)) )
              in
              (match vars with
              | [] -> f
              | v :: rest -> List.fold_left (fun acc x -> FAnd (acc, var_formula x)) (var_formula v) rest)
    end

let simplify_for_display (f : fo) : fo =
  match f with
  | FImp (cond, body) -> FImp (cond, simplify_assume_dnf_bool_domain body) |> Fo_simplifier.simplify_fo
  | _ -> simplify_assume_dnf_bool_domain f |> Fo_simplifier.simplify_fo

let string_of_fo_display (f : fo) : string = string_of_fo (simplify_for_display f)

let debug_contract_ids =
  ref (match Sys.getenv_opt "OBC2WHY3_DEBUG_CONTRACT_IDS" with Some "1" -> true | _ -> false)

let set_debug_contract_ids (b : bool) : unit = debug_contract_ids := b
let debug_contract_ids_enabled () : bool = !debug_contract_ids

let transition_lines (indent : int) (t : transition) ~(init_for_var : ident -> iexpr)
    ~(vars : ident list) ~(label_counters : label_counters) ~(label_align_col : int option) :
    string list =
  let next_req_label () =
    label_counters.req <- label_counters.req + 1;
    Printf.sprintf "H%d" label_counters.req
  in
  let next_ens_label () =
    label_counters.ens <- label_counters.ens + 1;
    Printf.sprintf "G%d" label_counters.ens
  in
  let guard = match t.guard with None -> "" | Some g -> " [" ^ string_of_iexpr g ^ "]" in
  let header = indent_str indent ^ t.src ^ " -> " ^ t.dst ^ guard ^ " {" in
  let requires_labeled = List.map (fun f -> (f, next_req_label ())) t.requires in
  let ensures_labeled = List.map (fun f -> (f, next_ens_label ())) t.ensures in
  let debug_ids = debug_contract_ids_enabled () in
  let build_block ~is_require items =
    let items =
      List.map (fun (f, label) -> (source_of_fo ~is_require f, f, label)) items
      |> List.sort (fun (s1, _, _) (s2, _, _) ->
          let c = compare (source_order s1) (source_order s2) in
          if c <> 0 then c else compare s1 s2)
    in
    let rec build acc current_source = function
      | [] -> acc
      | (source, f, label) :: rest ->
          let header =
            if Some source = current_source then []
            else [ comment_line (indent + 1) ("source: " ^ source) ]
          in
          let vcid_line = [] in
          let line =
            let kw = if is_require then "assumes " else "guarantees " in
            indent_str (indent + 1) ^ kw ^ string_of_fo_display f.value ^ ";"
          in
          let line = prettify_pre_old ~init_for_var ~vars line in
          let line =
            if not debug_ids then line
            else
              let src = source_of_fo ~is_require f in
              let kind = if is_require then "req" else "ens" in
              Printf.sprintf "%s  (* %s oid=%d src=%s %s->%s *)" line kind f.oid src t.src
                t.dst
          in
          let line =
            match label_align_col with
            | None -> line ^ "  (* " ^ label ^ " *)"
            | Some col ->
                let pad =
                  let n = col - String.length line in
                  if n <= 1 then " " else String.make n ' '
                in
                line ^ pad ^ "(* " ^ label ^ " *)"
          in
          build (acc @ header @ vcid_line @ [ line ]) (Some source) rest
    in
    build [] None items
  in
  let req_block =
    if requires_labeled = [] then []
    else comment_line (indent + 1) "-- assumes --" :: build_block ~is_require:true requires_labeled
  in
  let ens_block =
    if ensures_labeled = [] then []
    else comment_line (indent + 1) "-- guarantees --" :: build_block ~is_require:false ensures_labeled
  in
  let body_ghost = t.attrs.ghost in
  let body_user = t.body in
  let body_mon = t.attrs.instrumentation in
  let ghost_lines =
    stmt_lines ~allow_empty:true (indent + 1) body_ghost
    |> List.map (prettify_pre_old ~init_for_var ~vars)
  in
  let body_lines =
    stmt_lines ~allow_empty:true (indent + 1) body_user
    |> List.map (prettify_pre_old ~init_for_var ~vars)
  in
  let ghost_header = [] in
  let user_header =
    if body_user = [] then [] else [ comment_line (indent + 1) "-- user code --" ]
  in
  let mon_header =
    if body_mon = [] then [] else [ comment_line (indent + 1) "-- automata update code --" ]
  in
  let body_mon_lines =
    stmt_lines ~allow_empty:true ~with_comments:false (indent + 1) body_mon
    |> List.map (prettify_pre_old ~init_for_var ~vars)
  in
  let footer = indent_str indent ^ "}" in
  [ header ] @ req_block @ ens_block @ ghost_header @ ghost_lines @ user_header @ body_lines
  @ mon_header @ body_mon_lines @ [ footer ]

let node_lines (n : node) : string list =
  let n = replace_pre_k_node n in
  let var_types = List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs) in
  let init_for_var =
   fun v ->
    match List.assoc_opt v var_types with
    | Some TBool -> mk_bool false
    | Some TInt -> mk_int 0
    | Some TReal -> mk_int 0
    | Some (TCustom _) | None -> mk_int 0
  in
  let vars = List.map fst var_types in
  let header =
    "node " ^ n.nname ^ " (" ^ params_of_vdecls n.inputs ^ ")" ^ " returns ("
    ^ params_of_vdecls n.outputs ^ ")"
  in
  let spec = Ast.specification_of_node n in
  let contracts =
    contract_lines 1 spec.spec_assumes spec.spec_guarantees ~invariants_user:n.attrs.invariants_user
      ~invariants_state_rel:spec.spec_invariants_state_rel ~init_for_var ~vars
    @ coherency_goal_lines 1 ~goals:n.attrs.coherency_goals ~init_for_var ~vars
  in
  let instances =
    match n.instances with
    | [] -> []
    | _ ->
        let inst_lines =
          List.map
            (fun (inst, node_name) -> indent_str 1 ^ "instance " ^ inst ^ ": " ^ node_name ^ ";")
            n.instances
        in
        (indent_str 1 ^ "instances") :: inst_lines
  in
  let locals =
    match n.locals with
    | [] -> []
    | _ ->
        let local_line v =
          let base = indent_str 2 ^ vdecl_line v ^ ";" in
          match local_comment v.vname with None -> base | Some msg -> base ^ " (* " ^ msg ^ " *)"
        in
        (indent_str 1 ^ "locals") :: List.map local_line n.locals
  in
  let states =
    let states_with_init =
      List.map
        (fun s -> if String.equal s n.init_state then s ^ "(init)" else s)
        n.states
    in
    indent_str 1 ^ "states " ^ String.concat ", " states_with_init ^ ";"
  in
  let label_counters = { req = 0; ens = 0 } in
  let label_align_col =
    let base_line_len is_require f =
      let kw = if is_require then "assumes " else "guarantees " in
      let line = indent_str 3 ^ kw ^ string_of_fo_display f ^ ";" in
      String.length (prettify_pre_old ~init_for_var ~vars line)
    in
    let lens =
      List.concat_map
        (fun (t : transition) ->
          List.map (base_line_len true) (Ast_provenance.values t.requires)
          @ List.map (base_line_len false) (Ast_provenance.values t.ensures))
        n.trans
    in
    match lens with
    | [] -> None
    | _ ->
        let max_len = List.fold_left max 0 lens in
        Some (max_len + 2)
  in
  let trans =
    (indent_str 1 ^ "transitions")
    :: List.concat_map
         (fun t -> transition_lines 2 t ~init_for_var ~vars ~label_counters ~label_align_col)
         n.trans
  in
  [ header ] @ contracts @ instances @ locals @ [ states ] @ trans @ [ "end" ]

let string_of_program (p : Ast.program) : string =
  let p = p in
  String.concat "\n" (List.map (fun n -> String.concat "\n" (node_lines n)) p) ^ "\n"

let compile_program (p : Ast.program) : string = string_of_program p

type line_with_vcid = string * int option

let coherency_goal_lines_with_vcid (indent : int) ~(goals : fo_o list)
    ~(init_for_var : ident -> iexpr) ~(vars : ident list) : line_with_vcid list =
  if goals = [] then []
  else
    let is_init_goal = function FImp (FTrue, _) -> true | _ -> false in
    let compare_goal a b = compare (string_of_fo a.value) (string_of_fo b.value) in
    let init_goals, transition_goals = List.partition (fun f -> is_init_goal f.value) goals in
    let emit_group acc title group next_id =
      if group = [] then (acc, next_id)
      else
        let group = List.sort compare_goal group in
        let lines, next_id =
          List.fold_left
            (fun (acc, id) f ->
              let line = indent_str indent ^ "goal " ^ string_of_fo_display f.value ^ ";" in
              let line = prettify_pre_old ~init_for_var ~vars line in
              (acc @ [ (line ^ "  (* C" ^ string_of_int id ^ " *)", Some f.oid) ], id + 1))
            ([], next_id) group
        in
        (acc @ [ (comment_line indent title, None) ] @ lines, next_id)
    in
    let acc, next_id = emit_group [] "-- coherency goals (init) --" init_goals 1 in
    let acc, _ = emit_group acc "-- coherency goals (transitions) --" transition_goals next_id in
    acc

let transition_lines_with_vcid (indent : int) (t : transition) ~(init_for_var : ident -> iexpr)
    ~(vars : ident list) ~(label_counters : label_counters) ~(label_align_col : int option) :
    line_with_vcid list =
  let next_req_label () =
    label_counters.req <- label_counters.req + 1;
    Printf.sprintf "H%d" label_counters.req
  in
  let next_ens_label () =
    label_counters.ens <- label_counters.ens + 1;
    Printf.sprintf "G%d" label_counters.ens
  in
  let guard = match t.guard with None -> "" | Some g -> " [" ^ string_of_iexpr g ^ "]" in
  let header = (indent_str indent ^ t.src ^ " -> " ^ t.dst ^ guard ^ " {", None) in
  let requires_labeled = List.map (fun f -> (f, next_req_label ())) t.requires in
  let ensures_labeled = List.map (fun f -> (f, next_ens_label ())) t.ensures in
  let debug_ids = debug_contract_ids_enabled () in
  let build_block ~is_require items =
    let items =
      List.map
        (fun (f, label) ->
          let vcid = Some f.oid in
          (source_of_fo ~is_require f, f, label, vcid))
        items
      |> List.sort (fun (s1, _, _, _) (s2, _, _, _) ->
          let c = compare (source_order s1) (source_order s2) in
          if c <> 0 then c else compare s1 s2)
    in
    let rec build acc current_source = function
      | [] -> acc
      | (source, f, label, vcid) :: rest ->
          let header =
            if Some source = current_source then []
            else [ (comment_line (indent + 1) ("source: " ^ source), None) ]
          in
          let vcid_line = [] in
          let line =
            let kw = if is_require then "assumes " else "guarantees " in
            indent_str (indent + 1) ^ kw ^ string_of_fo_display f.value ^ ";"
          in
          let line = prettify_pre_old ~init_for_var ~vars line in
          let line =
            if not debug_ids then line
            else
              let src = source_of_fo ~is_require f in
              let kind = if is_require then "req" else "ens" in
              Printf.sprintf "%s  (* %s oid=%d src=%s %s->%s *)" line kind f.oid src t.src
                t.dst
          in
          let line =
            match label_align_col with
            | None -> line ^ "  (* " ^ label ^ " *)"
            | Some col ->
                let pad =
                  let n = col - String.length line in
                  if n <= 1 then " " else String.make n ' '
                in
                line ^ pad ^ "(* " ^ label ^ " *)"
          in
          build (acc @ header @ vcid_line @ [ (line, vcid) ]) (Some source) rest
    in
    build [] None items
  in
  let req_block =
    if requires_labeled = [] then []
    else
      (comment_line (indent + 1) "-- assumes --", None)
      :: build_block ~is_require:true requires_labeled
  in
  let ens_block =
    if ensures_labeled = [] then []
    else
      (comment_line (indent + 1) "-- guarantees --", None)
      :: build_block ~is_require:false ensures_labeled
  in
  let body_ghost = t.attrs.ghost in
  let body_user = t.body in
  let body_mon = t.attrs.instrumentation in
  let ghost_lines =
    stmt_lines ~allow_empty:true (indent + 1) body_ghost
    |> List.map (prettify_pre_old ~init_for_var ~vars)
    |> List.map (fun line -> (line, None))
  in
  let body_lines =
    stmt_lines ~allow_empty:true (indent + 1) body_user
    |> List.map (prettify_pre_old ~init_for_var ~vars)
    |> List.map (fun line -> (line, None))
  in
  let ghost_header = [] in
  let user_header =
    if body_user = [] then [] else [ (comment_line (indent + 1) "-- user code --", None) ]
  in
  let mon_header =
    if body_mon = [] then [] else [ (comment_line (indent + 1) "-- automata update code --", None) ]
  in
  let body_mon_lines =
    stmt_lines ~allow_empty:true ~with_comments:false (indent + 1) body_mon
    |> List.map (prettify_pre_old ~init_for_var ~vars)
    |> List.map (fun line -> (line, None))
  in
  let footer = (indent_str indent ^ "}", None) in
  [ header ] @ req_block @ ens_block @ ghost_header @ ghost_lines @ user_header @ body_lines
  @ mon_header @ body_mon_lines @ [ footer ]

let node_lines_with_vcid (n : node) : line_with_vcid list =
  let n = replace_pre_k_node n in
  let var_types = List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs) in
  let init_for_var v =
    match List.assoc_opt v var_types with
    | Some TBool -> mk_bool false
    | Some TInt -> mk_int 0
    | Some TReal -> mk_int 0
    | Some (TCustom _) | None -> mk_int 0
  in
  let vars = List.map fst var_types in
  let header =
    let params =
      let params = params_of_vdecls n.inputs in
      if params = "" then "" else " (" ^ params ^ ")"
    in
    let returns =
      let returns = params_of_vdecls n.outputs in
      if returns = "" then "" else " returns (" ^ returns ^ ")"
    in
    (Printf.sprintf "node %s%s%s" n.nname params returns, None)
  in
  let spec = Ast.specification_of_node n in
  let contracts =
    contract_lines 1 spec.spec_assumes spec.spec_guarantees ~invariants_user:n.attrs.invariants_user
      ~invariants_state_rel:spec.spec_invariants_state_rel ~init_for_var ~vars
    |> List.map (fun line -> (line, None))
  in
  let coherency_goals =
    coherency_goal_lines_with_vcid 1 ~goals:n.attrs.coherency_goals ~init_for_var ~vars
  in
  let instances =
    match n.instances with
    | [] -> [ (indent_str 1 ^ "instances", None) ]
    | _ ->
        let inst_line (inst_name, node_name) =
          indent_str 2 ^ "instance " ^ inst_name ^ " : " ^ node_name ^ ";"
        in
        (indent_str 1 ^ "instances", None)
        :: List.map (fun line -> (line, None)) (List.map inst_line n.instances)
  in
  let locals =
    match n.locals with
    | [] -> []
    | _ ->
        let local_line v =
          let base = indent_str 2 ^ vdecl_line v ^ ";" in
          match local_comment v.vname with None -> base | Some msg -> base ^ " (* " ^ msg ^ " *)"
        in
        (indent_str 1 ^ "locals", None)
        :: List.map (fun line -> (line, None)) (List.map local_line n.locals)
  in
  let states =
    let states_with_init =
      List.map
        (fun s -> if String.equal s n.init_state then s ^ "(init)" else s)
        n.states
    in
    (indent_str 1 ^ "states " ^ String.concat ", " states_with_init ^ ";", None)
  in
  let label_counters = { req = 0; ens = 0 } in
  let label_align_col =
    let base_line_len is_require f =
      let kw = if is_require then "assumes " else "guarantees " in
      let line = indent_str 3 ^ kw ^ string_of_fo_display f ^ ";" in
      String.length (prettify_pre_old ~init_for_var ~vars line)
    in
    let lens =
      List.concat_map
        (fun (t : transition) ->
          List.map (base_line_len true) (Ast_provenance.values t.requires)
          @ List.map (base_line_len false) (Ast_provenance.values t.ensures))
        n.trans
    in
    match lens with
    | [] -> None
    | _ ->
        let max_len = List.fold_left max 0 lens in
        Some (max_len + 2)
  in
  let trans =
    (indent_str 1 ^ "transitions", None)
    :: List.concat_map
         (fun t ->
           transition_lines_with_vcid 2 t ~init_for_var ~vars ~label_counters ~label_align_col)
         n.trans
  in
  [ header ] @ contracts @ coherency_goals @ instances @ locals @ [ states ] @ trans
  @ [ ("end", None) ]

let string_of_program_with_spans (p : Ast.program) : string * (int * (int * int)) list =
  let p = p in
  let lines = List.concat_map node_lines_with_vcid p in
  let buf = Buffer.create 4096 in
  let spans = ref [] in
  let offset = ref 0 in
  let add_line (line, vcid_opt) =
    Buffer.add_string buf line;
    let line_len = String.length line in
    begin match vcid_opt with
    | None -> ()
    | Some vcid -> spans := (vcid, (!offset, !offset + line_len)) :: !spans
    end;
    Buffer.add_char buf '\n';
    offset := !offset + line_len + 1
  in
  List.iter add_line lines;
  (Buffer.contents buf, List.rev !spans)

let compile_program_with_spans (p : Ast.program) : string * (int * (int * int)) list =
  string_of_program_with_spans p
