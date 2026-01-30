(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

let indent_str (n:int) : string = String.make (2 * n) ' '

let starts_with (s:string) (prefix:string) : bool =
  let ls = String.length s in
  let lp = String.length prefix in
  ls >= lp && String.sub s 0 lp = prefix

let is_mon_ctor (s:string) : bool =
  let len = String.length s in
  len >= 4
  && String.sub s 0 3 = "Mon"
  && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub s 3 (len - 3))

let is_generated_ident (id:string) : bool =
  starts_with id "__mon_state"
  || starts_with id "__mon_"
  || starts_with id "__fold_internal_"
  || is_mon_ctor id

type gen_tag =
  | MonitorAtom
  | MonitorState
  | CompatInvariant
  | FoldInternal
  | PostForNextPre

let tag_label = function
  | MonitorAtom -> "monitor_atom"
  | MonitorState -> "monitor_state"
  | CompatInvariant -> "compat_invariant"
  | FoldInternal -> "fold_internal"
  | PostForNextPre -> "post_for_next_pre"

let rec iexpr_mentions_generated (e:iexpr) : bool =
  match e with
  | ILitInt _ | ILitBool _ -> false
  | IVar id -> is_generated_ident id
  | IPar e -> iexpr_mentions_generated e
  | IUn (_, e) -> iexpr_mentions_generated e
  | IBin (_, a, b) -> iexpr_mentions_generated a || iexpr_mentions_generated b

let rec iexpr_has_tag (tag:gen_tag) (e:iexpr) : bool =
  match e with
  | ILitInt _ | ILitBool _ -> false
  | IVar id ->
      begin match tag with
      | MonitorAtom -> false
      | MonitorState -> id = "__mon_state" || is_mon_ctor id
      | FoldInternal -> starts_with id "__fold_internal_"
      | CompatInvariant | PostForNextPre -> false
      end
  | IPar e -> iexpr_has_tag tag e
  | IUn (_, e) -> iexpr_has_tag tag e
  | IBin (_, a, b) -> iexpr_has_tag tag a || iexpr_has_tag tag b

let rec hexpr_mentions_generated (h:hexpr) : bool =
  match h with
  | HNow e -> iexpr_mentions_generated e
  | HPre e ->
      iexpr_mentions_generated e
  | HPreK (e, _) ->
      iexpr_mentions_generated e
  | HFold (_, init, e) ->
      iexpr_mentions_generated init || iexpr_mentions_generated e

let rec hexpr_has_tag (tag:gen_tag) (h:hexpr) : bool =
  match h with
  | HNow e -> iexpr_has_tag tag e
  | HPre e ->
      iexpr_has_tag tag e
  | HPreK (e, _) ->
      iexpr_has_tag tag e
  | HFold (_, init, e) ->
      iexpr_has_tag tag init || iexpr_has_tag tag e

let rec fo_mentions_generated (f:fo) : bool =
  match f with
  | FTrue | FFalse -> false
  | FRel (h1, _, h2) ->
      hexpr_mentions_generated h1 || hexpr_mentions_generated h2
  | FPred (_, hs) ->
      List.exists hexpr_mentions_generated hs
  | FNot a -> fo_mentions_generated a
  | FAnd (a, b) | FOr (a, b) | FImp (a, b) ->
      fo_mentions_generated a || fo_mentions_generated b

let rec fo_has_tag (tag:gen_tag) (f:fo) : bool =
  match f with
  | FTrue | FFalse -> false
  | FRel (h1, _, h2) ->
      hexpr_has_tag tag h1 || hexpr_has_tag tag h2
  | FPred (_, hs) ->
      List.exists (hexpr_has_tag tag) hs
  | FNot a -> fo_has_tag tag a
  | FAnd (a, b) | FOr (a, b) | FImp (a, b) ->
      fo_has_tag tag a || fo_has_tag tag b

let comment_line (indent:int) (msg:string) : string =
  indent_str indent ^ "(* " ^ msg ^ " *)"

let comment_for_tag indent tag =
  comment_line indent ("generated: " ^ tag_label tag)

let comment_for_tags indent tags =
  let tags = List.sort_uniq compare tags in
  let monitor_details =
    List.filter (function MonitorAtom | MonitorState | CompatInvariant -> true | _ -> false) tags
  in
  let other_tags =
    List.filter (function MonitorAtom | MonitorState | CompatInvariant -> false | _ -> true) tags
  in
  let monitor_line =
    match monitor_details with
    | [] -> []
    | _ -> [comment_line indent "generated: monitor"]
  in
  monitor_line @ (List.map (comment_for_tag indent) other_tags)

let tags_for_ident (id:string) : gen_tag list =
  let tags = ref [] in
  if starts_with id "__fold_internal_" then tags := FoldInternal :: !tags;
  if id = "__mon_state" || is_mon_ctor id then tags := MonitorState :: !tags;
  !tags

let tags_for_iexpr (e:iexpr) : gen_tag list =
  let tags = ref [] in
  if iexpr_has_tag MonitorState e then tags := MonitorState :: !tags;
  if iexpr_has_tag FoldInternal e then tags := FoldInternal :: !tags;
  !tags

let tags_for_fo (f:fo) : gen_tag list =
  let tags = ref [] in
  if fo_has_tag MonitorState f then tags := MonitorState :: !tags;
  if fo_has_tag FoldInternal f then tags := FoldInternal :: !tags;
  !tags

let add_semicolon (lines:string list) : string list =
  match List.rev lines with
  | [] -> []
  | last :: rest_rev -> List.rev ((last ^ ";") :: rest_rev)

let rec stmt_lines ?(allow_empty=true) ?(with_comments=true)
  (indent:int) (stmts:stmt list) : string list =
  match stmts with
  | [] -> if allow_empty then [] else [indent_str indent ^ "skip"]
  | _ ->
      List.concat_map
        (fun s -> add_semicolon (stmt_one_lines ~with_comments indent s))
        stmts

and stmt_one_lines ?(with_comments=true) (indent:int) (s:stmt) : string list =
  let tags =
    match s with
    | SAssign (id, e) -> tags_for_ident id @ tags_for_iexpr e
    | SIf (c, _, _) -> tags_for_iexpr c
    | SMatch (e, _, _) -> tags_for_iexpr e
    | SCall _ | SSkip -> []
  in
  let prefix = if with_comments then comment_for_tags indent tags else [] in
  match s with
  | SAssign (id, e) ->
      prefix @ [indent_str indent ^ id ^ " := " ^ string_of_iexpr e]
  | SSkip ->
      prefix @ [indent_str indent ^ "skip"]
  | SCall (inst, args, outs) ->
      let args_s = String.concat ", " (List.map string_of_iexpr args) in
      let outs_s = String.concat ", " outs in
      prefix @ [indent_str indent ^ "call " ^ inst ^ "(" ^ args_s ^ ") returns (" ^ outs_s ^ ")"]
  | SIf (cond, tbr, fbr) ->
      prefix @ [indent_str indent ^ "if " ^ string_of_iexpr cond ^ " then"]
      @ stmt_lines ~allow_empty:false ~with_comments (indent + 1) tbr
      @ [indent_str indent ^ "else"]
      @ stmt_lines ~allow_empty:false ~with_comments (indent + 1) fbr
      @ [indent_str indent ^ "end"]
  | SMatch (e, branches, def) ->
      prefix @ [indent_str indent ^ "match " ^ string_of_iexpr e ^ " with"]
      @ List.concat_map
          (fun (ctor, body) ->
             [indent_str indent ^ "| " ^ ctor ^ " ->"]
             @ stmt_lines ~allow_empty:false ~with_comments (indent + 1) body)
          branches
      @ (if def = [] then [] else
           [indent_str indent ^ "| _ ->"]
           @ stmt_lines ~allow_empty:false ~with_comments (indent + 1) def)
      @ [indent_str indent ^ "end"]

let vdecl_line (v:vdecl) : string =
  v.vname ^ ": " ^
  (match v.vty with
   | TInt -> "int"
   | TBool -> "bool"
   | TReal -> "real"
   | TCustom s -> s)

let params_of_vdecls (vs:vdecl list) : string =
  String.concat ", " (List.map vdecl_line vs)

let inline_iexpr (atom_map:(ident * iexpr) list) (e:iexpr) : iexpr =
  let tbl = Hashtbl.create 16 in
  List.iter (fun (id, ex) -> Hashtbl.replace tbl id ex) atom_map;
  let rec go = function
    | IVar id ->
        begin match Hashtbl.find_opt tbl id with
        | Some ex -> ex
        | None -> IVar id
        end
    | ILitInt _ | ILitBool _ as e -> e
    | IPar e -> IPar (go e)
    | IUn (op, e) -> IUn (op, go e)
    | IBin (op, a, b) -> IBin (op, go a, go b)
  in
  go e

let inline_hexpr atom_map ~(init_for_var:ident -> iexpr) ~(vars:ident list) = function
  | HNow e ->
      begin match inline_iexpr atom_map e with
      | IVar id when starts_with id "__pre_old_" ->
          let base = String.sub id 10 (String.length id - 10) in
          if List.mem base vars then
            HPre (IVar base)
          else
            HNow (IVar id)
      | e -> HNow e
      end
  | HPre e ->
      HPre (inline_iexpr atom_map e)
  | HPreK (e, k) ->
      HPreK (inline_iexpr atom_map e, k)
  | HFold (op, init, e) ->
      HFold (op, inline_iexpr atom_map init, inline_iexpr atom_map e)

let rec inline_fo atom_map ~init_for_var ~vars = function
  | FTrue | FFalse as f -> f
  | FRel (h1, r, h2) ->
      FRel (inline_hexpr atom_map ~init_for_var ~vars h1, r,
            inline_hexpr atom_map ~init_for_var ~vars h2)
  | FPred (id, hs) ->
      FPred (id, List.map (inline_hexpr atom_map ~init_for_var ~vars) hs)
  | FNot a -> FNot (inline_fo atom_map ~init_for_var ~vars a)
  | FAnd (a, b) -> FAnd (inline_fo atom_map ~init_for_var ~vars a,
                         inline_fo atom_map ~init_for_var ~vars b)
  | FOr (a, b) -> FOr (inline_fo atom_map ~init_for_var ~vars a,
                       inline_fo atom_map ~init_for_var ~vars b)
  | FImp (a, b) -> FImp (inline_fo atom_map ~init_for_var ~vars a,
                         inline_fo atom_map ~init_for_var ~vars b)

let replace_all ~sub ~by s =
  if sub = "" then s else
    let sub_len = String.length sub in
    let len = String.length s in
    let b = Buffer.create len in
    let rec loop i =
      if i >= len then ()
      else if i + sub_len <= len && String.sub s i sub_len = sub then (
        Buffer.add_string b by;
        loop (i + sub_len)
      ) else (
        Buffer.add_char b s.[i];
        loop (i + 1)
      )
    in
    loop 0;
    Buffer.contents b

let prettify_pre_old ~init_for_var ~vars s =
  List.fold_left
    (fun acc v ->
       let sub = "__pre_old_" ^ v in
       let by = "pre(" ^ v ^ ")" in
       replace_all ~sub ~by acc)
    s vars

let contract_lines (indent:int) (assumes:ltl list) (guarantees:ltl list)
  (invariants:invariant_mon list) (atom_map:(ident * iexpr) list)
  ~(init_for_var:ident -> iexpr) ~(vars:ident list) : string list =
  let assume_lines =
    List.map (fun f -> indent_str indent ^ "assume " ^ string_of_ltl f ^ ";") assumes
  in
  let guarantee_lines =
    List.map (fun f -> indent_str indent ^ "guarantee " ^ string_of_ltl f ^ ";") guarantees
  in
  let inv_lines =
    let add_with_prefix (acc, last_prefix) prefix line =
      if prefix = [] || prefix = last_prefix then
        (acc @ [line], last_prefix)
      else
        (acc @ prefix @ [line], prefix)
    in
    let rec build acc last_prefix = function
      | [] -> acc
      | inv :: rest ->
          begin
            match inv with
            | Invariant (id, h) ->
                let tags =
                  tags_for_ident id
                  @ (if hexpr_has_tag MonitorAtom h then [MonitorAtom] else [])
                  @ (if hexpr_has_tag MonitorState h then [MonitorState] else [])
                  @ (if hexpr_has_tag FoldInternal h then [FoldInternal] else [])
                in
                let prefix = comment_for_tags indent tags in
            let h = inline_hexpr atom_map ~init_for_var ~vars h in
            let line =
              indent_str indent ^ "(* invariant " ^ id ^ " = "
              ^ string_of_hexpr h ^ " *)"
            in
            let line = prettify_pre_old ~init_for_var ~vars line in
                let acc, last_prefix = add_with_prefix (acc, last_prefix) prefix line in
                build acc last_prefix rest
            | InvariantStateRel (is_eq, st, f) ->
                let op = if is_eq then "=" else "!=" in
                let tags = tags_for_fo f in
                let tags =
                  if fo_has_tag MonitorState f then CompatInvariant :: tags else tags
                in
                let prefix = comment_for_tags indent tags in
            let f = inline_fo atom_map ~init_for_var ~vars f in
            let line =
              indent_str indent ^ "(* invariant state " ^ op ^ " " ^ st ^ " -> "
              ^ string_of_fo f ^ " *)"
            in
            let line = prettify_pre_old ~init_for_var ~vars line in
                let acc, last_prefix = add_with_prefix (acc, last_prefix) prefix line in
                build acc last_prefix rest
          end
    in
    build [] [] invariants
  in
  assume_lines @ guarantee_lines @ inv_lines

let transition_lines (indent:int) (t:transition) (atom_map:(ident * iexpr) list)
  ~(init_for_var:ident -> iexpr) ~(vars:ident list)
  : string list =
  let is_monitor_tag = function
    | MonitorAtom | MonitorState -> true
    | CompatInvariant | FoldInternal | PostForNextPre -> false
  in
  let stmt_is_monitor (s:stmt) : bool =
    match s with
    | SAssign (id, e) ->
        let tags = tags_for_ident id @ tags_for_iexpr e in
        List.exists is_monitor_tag tags
    | SIf (c, _, _) | SMatch (c, _, _) ->
        List.exists is_monitor_tag (tags_for_iexpr c)
    | SCall _ | SSkip -> false
  in
  let split_monitor_suffix (stmts:stmt list) : stmt list * stmt list =
    let rec take_rev acc = function
      | [] -> ([], List.rev acc)
      | s :: rest ->
          if stmt_is_monitor s then
            take_rev (s :: acc) rest
          else
            (List.rev rest @ [s], List.rev acc)
    in
    take_rev [] (List.rev stmts)
  in
  let guard =
    match t.guard with
    | None -> ""
    | Some g -> " [" ^ string_of_iexpr g ^ "]"
  in
  let header = indent_str indent ^ t.src ^ " -> " ^ t.dst ^ guard ^ " {" in
  let split_user_generated fo_list =
    List.fold_left
      (fun (user, gen) f ->
         if tags_for_fo f = [] then (user @ [f], gen) else (user, gen @ [f]))
      ([], [])
      fo_list
  in
  let user_requires, gen_requires = split_user_generated t.requires in
  let user_ensures, gen_ensures = split_user_generated t.ensures in
  let user_req_block =
    match user_requires with
    | [] -> []
    | _ ->
        [comment_line (indent + 1) "user requires"]
        @ (let rec build acc last_prefix = function
             | [] -> acc
             | f :: rest ->
          let f = inline_fo atom_map ~init_for_var ~vars f in
          let prefix = comment_for_tags (indent + 1) (tags_for_fo f) in
          let line =
            indent_str (indent + 1) ^ "requires " ^ string_of_fo f ^ ";"
          in
          let line = prettify_pre_old ~init_for_var ~vars line in
                 let acc, last_prefix =
                   if prefix = [] || prefix = last_prefix then
                     (acc @ [line], last_prefix)
                   else
                     (acc @ prefix @ [line], prefix)
                 in
                 build acc last_prefix rest
           in
           build [] [] user_requires)
  in
  let gen_req_block =
    match gen_requires with
    | [] -> []
    | _ ->
        (let rec build acc last_prefix = function
          | [] -> acc
          | f :: rest ->
              let f = inline_fo atom_map ~init_for_var ~vars f in
              let prefix = comment_for_tags (indent + 1) (tags_for_fo f) in
              let line =
                indent_str (indent + 1) ^ "requires " ^ string_of_fo f ^ ";"
              in
              let line = prettify_pre_old ~init_for_var ~vars line in
              let acc, last_prefix =
                if prefix = [] || prefix = last_prefix then
                  (acc @ [line], last_prefix)
                else
                  (acc @ prefix @ [line], prefix)
              in
              build acc last_prefix rest
         in
         build [] [] gen_requires)
  in
  let user_ens_block =
    match user_ensures with
    | [] -> []
    | _ ->
        [comment_line (indent + 1) "user ensures"]
        @ (let rec build acc last_prefix = function
             | [] -> acc
             | f :: rest ->
          let f = inline_fo atom_map ~init_for_var ~vars f in
          let prefix = comment_for_tags (indent + 1) (tags_for_fo f) in
          let line =
            indent_str (indent + 1) ^ "ensures " ^ string_of_fo f ^ ";"
          in
          let line = prettify_pre_old ~init_for_var ~vars line in
                 let acc, last_prefix =
                   if prefix = [] || prefix = last_prefix then
                     (acc @ [line], last_prefix)
                   else
                     (acc @ prefix @ [line], prefix)
                 in
                 build acc last_prefix rest
           in
           build [] [] user_ensures)
  in
  let gen_ens_block =
    match gen_ensures with
    | [] -> []
    | _ ->
        (let rec build acc last_prefix = function
          | [] -> acc
          | f :: rest ->
              let f = inline_fo atom_map ~init_for_var ~vars f in
              let prefix = comment_for_tags (indent + 1) (tags_for_fo f) in
              let line =
                indent_str (indent + 1) ^ "ensures " ^ string_of_fo f ^ ";"
              in
              let line = prettify_pre_old ~init_for_var ~vars line in
              let acc, last_prefix =
                if prefix = [] || prefix = last_prefix then
                  (acc @ [line], last_prefix)
                else
                  (acc @ prefix @ [line], prefix)
              in
              build acc last_prefix rest
         in
         build [] [] gen_ensures)
  in
  let lemma_lines =
    List.map
      (fun f ->
         let f = inline_fo atom_map ~init_for_var ~vars f in
         let line =
           indent_str (indent + 1) ^ "(* lemma " ^ string_of_fo f ^ " *)"
         in
         let line = prettify_pre_old ~init_for_var ~vars line in
         comment_for_tag (indent + 1) PostForNextPre :: [line]
      )
      t.lemmas
  in
  let body_user, body_mon = split_monitor_suffix t.body in
  let body_lines =
    stmt_lines ~allow_empty:true (indent + 1) body_user
    |> List.map (prettify_pre_old ~init_for_var ~vars)
  in
  let mon_header =
    if body_mon = [] then []
    else [comment_line (indent + 1) "monitor code (generated)"]
  in
  let body_mon_lines =
    stmt_lines ~allow_empty:true ~with_comments:false (indent + 1) body_mon
    |> List.map (prettify_pre_old ~init_for_var ~vars)
  in
  let footer = indent_str indent ^ "}" in
  [header]
  @ user_req_block @ gen_req_block @ user_ens_block @ gen_ens_block
  @ List.concat lemma_lines
  @ body_lines
  @ mon_header @ body_mon_lines
  @ [footer]

let node_lines (n:node) : string list =
  let atom_map =
    n.invariants_mon
    |> List.filter_map (function
         | Invariant (id, HNow e) when starts_with id "atom_" -> Some (id, e)
         | _ -> None)
  in
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let init_for_var =
    fun v ->
      match List.assoc_opt v var_types with
      | Some TBool -> ILitBool false
      | Some TInt -> ILitInt 0
      | Some TReal -> ILitInt 0
      | Some (TCustom _) | None -> ILitInt 0
  in
  let vars = List.map fst var_types in
  let header =
    "node " ^ n.nname ^ " (" ^ params_of_vdecls n.inputs ^ ")"
    ^ " returns (" ^ params_of_vdecls n.outputs ^ ")"
  in
  let contracts =
    contract_lines 1 n.assumes n.guarantees n.invariants_mon atom_map
      ~init_for_var ~vars
  in
  let instances =
    match n.instances with
    | [] -> []
    | _ ->
        let inst_lines =
          List.map
            (fun (inst, node_name) ->
               indent_str 1 ^ "instance " ^ inst ^ ": " ^ node_name ^ ";")
            n.instances
        in
        (indent_str 1 ^ "instances") :: inst_lines
  in
  let locals =
    match n.locals with
    | [] -> [indent_str 1 ^ "locals"]
    | _ ->
        (indent_str 1 ^ "locals")
        :: List.map (fun v -> indent_str 2 ^ vdecl_line v ^ ";") n.locals
  in
  let states =
    indent_str 1 ^ "states " ^ String.concat ", " n.states ^ ";"
  in
  let init = indent_str 1 ^ "init " ^ n.init_state in
  let trans =
    (indent_str 1 ^ "trans")
    :: List.concat_map
         (fun t -> transition_lines 2 t atom_map ~init_for_var ~vars)
         n.trans
  in
  [header]
  @ contracts
  @ instances
  @ locals
  @ [states; init]
  @ trans
  @ ["end"]

let string_of_program (p:program) : string =
  String.concat "\n" (List.map (fun n -> String.concat "\n" (node_lines n)) p) ^ "\n"

let compile_program_monitor (p:program) : string =
  let p' = List.map Monitor_transform.transform_node_monitor p in
  string_of_program p'
