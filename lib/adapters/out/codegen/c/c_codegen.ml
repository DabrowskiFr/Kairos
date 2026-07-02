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

open Core_syntax

type generated_file = {
  file_name : string;
  contents : string;
}

let ( let* ) = Result.bind

module StringSet = Set.Make (String)

let errorf fmt = Printf.ksprintf (fun msg -> Error msg) fmt

let map_result f xs =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | x :: rest ->
        let* y = f x in
        loop (y :: acc) rest
  in
  loop [] xs

let concat_map_result f xs =
  let* chunks = map_result f xs in
  Ok (List.concat chunks)

let c_keywords =
  [
    "auto";
    "break";
    "case";
    "char";
    "const";
    "continue";
    "default";
    "do";
    "double";
    "else";
    "enum";
    "extern";
    "float";
    "for";
    "goto";
    "if";
    "inline";
    "int";
    "long";
    "register";
    "restrict";
    "return";
    "short";
    "signed";
    "sizeof";
    "static";
    "struct";
    "switch";
    "typedef";
    "union";
    "unsigned";
    "void";
    "volatile";
    "while";
    "_Alignas";
    "_Alignof";
    "_Atomic";
    "_Bool";
    "_Complex";
    "_Generic";
    "_Imaginary";
    "_Noreturn";
    "_Static_assert";
    "_Thread_local";
  ]

let c_keyword_set =
  List.fold_left (fun acc kw -> StringSet.add kw acc) StringSet.empty c_keywords

let is_ident_start = function
  | 'A' .. 'Z' | 'a' .. 'z' | '_' -> true
  | _ -> false

let is_ident_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true
  | _ -> false

let sanitize_ident raw =
  let b = Buffer.create (String.length raw + 8) in
  String.iter
    (fun c -> Buffer.add_char b (if is_ident_char c then c else '_'))
    raw;
  let s = Buffer.contents b in
  let s = if s = "" then "x" else s in
  let s = if is_ident_start s.[0] then s else "_" ^ s in
  if StringSet.mem s c_keyword_set then s ^ "_" else s

let upper_ident s = String.uppercase_ascii (sanitize_ident s)
let indent n = String.make (2 * n) ' '
let line n s = indent n ^ s
let blank = ""
let join_lines lines = String.concat "\n" lines ^ "\n"

let c_type_name = function
  | TInt -> "int"
  | TBool -> "bool"
  | TReal -> "double"
  | TCustom name -> sanitize_ident name ^ "_t"

let zero_value = function
  | TInt -> "0"
  | TBool -> "false"
  | TReal -> "0.0"
  | TCustom name -> "(" ^ c_type_name (TCustom name) ^ ")0"

let enum_type_name name = sanitize_ident name ^ "_t"
let enum_ctor_name type_name ctor = "KAIROS_" ^ upper_ident type_name ^ "_" ^ upper_ident ctor
let node_base_name (node : Verification_model.node_model) = sanitize_ident node.node_name
let state_type_name node = node_base_name node ^ "_state_t"
let control_state_type_name node = node_base_name node ^ "_control_state_t"
let init_function_name node = node_base_name node ^ "_init"
let step_function_name node = node_base_name node ^ "_step"
let control_state_ctor node state = "KAIROS_" ^ upper_ident (node_base_name node) ^ "_STATE_" ^ upper_ident state
let pure_function_name name = "kairos_fn_" ^ sanitize_ident name
let input_name v = "in_" ^ sanitize_ident v.vname
let input_name_of_ident name = "in_" ^ sanitize_ident name
let output_tmp_name v = "tmp_" ^ sanitize_ident v.vname
let output_tmp_name_of_ident name = "tmp_" ^ sanitize_ident name
let output_pointer_name v = "out_" ^ sanitize_ident v.vname
let field_name v = "field_" ^ sanitize_ident v.vname
let field_name_of_ident name = "field_" ^ sanitize_ident name
let function_param_name v = "arg_" ^ sanitize_ident v.vname
let function_param_name_of_ident name = "arg_" ^ sanitize_ident name

type program_env = { enum_ctor_types : (ident, ident) Hashtbl.t }

type variable_scope = ident -> string option

type expr_env = {
  program_env : program_env;
  variable_name : variable_scope;
}

let enum_ctor_c_name env ctor =
  match Hashtbl.find_opt env.program_env.enum_ctor_types ctor with
  | Some type_name -> Ok (enum_ctor_name type_name ctor)
  | None -> errorf "unknown enum constructor '%s'" ctor

let binop_text = function
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | And -> "&&"
  | Or -> "||"

let relop_text = function
  | REq -> "=="
  | RNeq -> "!="
  | RLt -> "<"
  | RLe -> "<="
  | RGt -> ">"
  | RGe -> ">="

let condition_text text =
  let len = String.length text in
  if len >= 2 && text.[0] = '(' && text.[len - 1] = ')' then text else "(" ^ text ^ ")"

let rec c_expr env (e : expr) =
  match e.expr with
  | ELitInt n -> Ok (string_of_int n)
  | ELitBool true -> Ok "true"
  | ELitBool false -> Ok "false"
  | ELitEnum ctor -> enum_ctor_c_name env ctor
  | EVar name -> (
      match env.variable_name name with
      | Some c_name -> Ok c_name
      | None -> errorf "unknown variable '%s' in executable expression" name)
  | EFunCall (fn, args) ->
      let* args = map_result (c_expr env) args in
      Ok (pure_function_name fn ^ "(" ^ String.concat ", " args ^ ")")
  | EBin (op, left, right) ->
      let* left = c_expr env left in
      let* right = c_expr env right in
      Ok ("(" ^ left ^ " " ^ binop_text op ^ " " ^ right ^ ")")
  | ECmp (op, left, right) ->
      let* left = c_expr env left in
      let* right = c_expr env right in
      Ok ("(" ^ left ^ " " ^ relop_text op ^ " " ^ right ^ ")")
  | EUn (Neg, inner) ->
      let* inner = c_expr env inner in
      Ok ("(-" ^ inner ^ ")")
  | EUn (Not, inner) ->
      let* inner = c_expr env inner in
      Ok ("(!" ^ inner ^ ")")

let rec c_hexpr env (h : hexpr) =
  match h.hexpr with
  | HLitInt n -> Ok (string_of_int n)
  | HLitBool true -> Ok "true"
  | HLitBool false -> Ok "false"
  | HLitEnum ctor -> enum_ctor_c_name env ctor
  | HVar name -> (
      match env.variable_name name with
      | Some c_name -> Ok c_name
      | None -> errorf "unknown variable '%s' in assertion expression" name)
  | HPreK (name, k) ->
      errorf "historical expression pre^%d(%s) cannot be emitted as a C runtime assertion" k name
  | HPred (name, _) -> errorf "predicate '%s' cannot be emitted as a C runtime assertion" name
  | HFunCall (fn, args) ->
      let* args = map_result (c_hexpr env) args in
      Ok (pure_function_name fn ^ "(" ^ String.concat ", " args ^ ")")
  | HBin (op, left, right) ->
      let* left = c_hexpr env left in
      let* right = c_hexpr env right in
      Ok ("(" ^ left ^ " " ^ binop_text op ^ " " ^ right ^ ")")
  | HCmp (op, left, right) ->
      let* left = c_hexpr env left in
      let* right = c_hexpr env right in
      Ok ("(" ^ left ^ " " ^ relop_text op ^ " " ^ right ^ ")")
  | HUn (Neg, inner) ->
      let* inner = c_hexpr env inner in
      Ok ("(-" ^ inner ^ ")")
  | HUn (Not, inner) ->
      let* inner = c_hexpr env inner in
      Ok ("(!" ^ inner ^ ")")

type node_env = {
  expr_env : expr_env;
  node : Verification_model.node_model;
  input_names : StringSet.t;
  output_names : StringSet.t;
  local_names : StringSet.t;
  ghost_names : StringSet.t;
}

let set_of_vdecls decls =
  List.fold_left (fun acc (v : vdecl) -> StringSet.add v.vname acc) StringSet.empty decls

let node_variable_name input_names output_names local_names ghost_names name =
  if StringSet.mem name input_names then Some (input_name_of_ident name)
  else if StringSet.mem name output_names then Some (output_tmp_name_of_ident name)
  else if StringSet.mem name local_names || StringSet.mem name ghost_names then
    Some ("state->" ^ field_name_of_ident name)
  else None

let node_env program_env (node : Verification_model.node_model) =
  let input_names = set_of_vdecls node.inputs in
  let output_names = set_of_vdecls node.outputs in
  let local_names = set_of_vdecls node.locals in
  let ghost_names = set_of_vdecls node.ghosts in
  let variable_name =
    node_variable_name input_names output_names local_names ghost_names
  in
  { expr_env = { program_env; variable_name }; node; input_names; output_names; local_names; ghost_names }

let lvalue_of_ident env name =
  if StringSet.mem name env.input_names then errorf "cannot assign to input '%s'" name
  else if StringSet.mem name env.output_names then Ok (output_tmp_name_of_ident name)
  else if StringSet.mem name env.local_names || StringSet.mem name env.ghost_names then
    Ok ("state->" ^ field_name_of_ident name)
  else errorf "unknown assignment target '%s'" name

let rec emit_stmt env level (s : stmt) =
  match s.stmt with
  | SAssign (target, rhs) ->
      let* target = lvalue_of_ident env target in
      let* rhs = c_expr env.expr_env rhs in
      Ok [ line level (target ^ " = " ^ rhs ^ ";") ]
  | SAssert formula ->
      let* formula = c_hexpr env.expr_env formula in
      Ok [ line level ("assert(" ^ formula ^ ");") ]
  | SIf (cond, then_stmts, else_stmts) ->
      let* cond = c_expr env.expr_env cond in
      let* then_lines = emit_stmts env (level + 1) then_stmts in
      let* else_lines = emit_stmts env (level + 1) else_stmts in
      let open_line = line level ("if " ^ condition_text cond ^ " {") in
      let close_line = line level "}" in
      if else_lines = [] then Ok (open_line :: then_lines @ [ close_line ])
      else
        Ok
          (open_line :: then_lines
          @ [ line level "} else {" ]
          @ else_lines @ [ close_line ])
  | SWhile (cond, _invariants, _variant, body) ->
      let* cond = c_expr env.expr_env cond in
      let* body_lines = emit_stmts env (level + 1) body in
      Ok (line level ("while " ^ condition_text cond ^ " {") :: body_lines @ [ line level "}" ])
  | SMatch (scrutinee, branches, default_branch) ->
      let* scrutinee = c_expr env.expr_env scrutinee in
      let emit_branch (ctor, stmts) =
        let* ctor = enum_ctor_c_name env.expr_env ctor in
        let* body_lines = emit_stmts env (level + 1) stmts in
        Ok (line level ("case " ^ ctor ^ ":") :: body_lines @ [ line (level + 1) "break;" ])
      in
      let* branch_lines = concat_map_result emit_branch branches in
      let* default_lines = emit_stmts env (level + 1) default_branch in
      let default_block =
        if default_lines = [] then []
        else line level "default:" :: default_lines @ [ line (level + 1) "break;" ]
      in
      Ok (line level ("switch (" ^ scrutinee ^ ") {") :: branch_lines @ default_block @ [ line level "}" ])
  | SSkip -> Ok []
  | SCall (callee, _, _) ->
      errorf "node call '%s' is not supported by the C backend yet" callee

and emit_stmts env level stmts = concat_map_result (emit_stmt env level) stmts

let function_scope params name =
  let rec find = function
    | [] -> None
    | (v : vdecl) :: rest ->
        if String.equal v.vname name then Some (function_param_name_of_ident name) else find rest
  in
  find params

let function_signature (f : pure_function_decl) =
  let params =
    List.map
      (fun (v : vdecl) -> c_type_name v.vty ^ " " ^ function_param_name v)
      f.function_params
  in
  let params = if params = [] then [ "void" ] else params in
  "static inline " ^ c_type_name f.function_return ^ " " ^ pure_function_name f.function_name ^ "("
  ^ String.concat ", " params ^ ")"

let emit_function_prototype f = function_signature f ^ ";"

let emit_function_definition program_env (f : pure_function_decl) =
  let env = { program_env; variable_name = function_scope f.function_params } in
  let* body = c_expr env f.function_body in
  Ok
    [
      function_signature f ^ " {";
      line 1 ("return " ^ body ^ ";");
      "}";
    ]

let emit_enum_decl (decl : enum_decl) =
  let ctors =
    List.mapi
      (fun index ctor -> line 1 (enum_ctor_name decl.enum_name ctor ^ " = " ^ string_of_int index))
      decl.enum_constructors
  in
  [
    "typedef enum {";
    String.concat ",\n" ctors;
    "} " ^ enum_type_name decl.enum_name ^ ";";
  ]

let node_control_enum node =
  let ctors =
    List.mapi
      (fun index state -> line 1 (control_state_ctor node state ^ " = " ^ string_of_int index))
      node.Verification_model.states
  in
  [
    "typedef enum {";
    String.concat ",\n" ctors;
    "} " ^ control_state_type_name node ^ ";";
  ]

let node_state_struct node =
  let fields =
    [ line 1 (control_state_type_name node ^ " control_state;") ]
    @ List.map
        (fun (v : vdecl) -> line 1 (c_type_name v.vty ^ " " ^ field_name v ^ ";"))
        (node.Verification_model.outputs @ node.locals @ node.ghosts)
  in
  [ "typedef struct {" ] @ fields @ [ "} " ^ state_type_name node ^ ";" ]

let step_params node =
  [ state_type_name node ^ " *state" ]
  @ List.map (fun (v : vdecl) -> c_type_name v.vty ^ " " ^ input_name v) node.inputs
  @ List.map
      (fun (v : vdecl) -> c_type_name v.vty ^ " *" ^ output_pointer_name v)
      node.outputs

let init_prototype node = "void " ^ init_function_name node ^ "(" ^ state_type_name node ^ " *state);"

let step_prototype node =
  "void " ^ step_function_name node ^ "(" ^ String.concat ", " (step_params node) ^ ");"

let emit_node_header node =
  node_control_enum node @ [ blank ] @ node_state_struct node @ [ blank; init_prototype node; step_prototype node ]

let emit_init_function node =
  let field_init_lines =
    List.map
      (fun (v : vdecl) -> line 1 ("state->" ^ field_name v ^ " = " ^ zero_value v.vty ^ ";"))
      (node.Verification_model.outputs @ node.locals @ node.ghosts)
  in
  [
    "void " ^ init_function_name node ^ "(" ^ state_type_name node ^ " *state) {";
    line 1 ("state->control_state = " ^ control_state_ctor node node.init_state ^ ";");
  ]
  @ field_init_lines @ [ "}" ]

let emit_transition env level (step : Verification_model.program_step) =
  let* body_lines = emit_stmts env (level + 1) step.body_stmts in
  let finish_lines =
    [
      line (level + 1) ("state->control_state = " ^ control_state_ctor env.node step.dst_state ^ ";");
      line (level + 1) "break;";
    ]
  in
  match step.guard_expr with
  | None -> Ok (line level "{" :: body_lines @ finish_lines @ [ line level "}" ])
  | Some guard ->
      let* guard = c_expr env.expr_env guard in
      Ok (line level ("if " ^ condition_text guard ^ " {") :: body_lines @ finish_lines @ [ line level "}" ])

let emit_state_case env steps state =
  let state_steps = List.filter (fun (s : Verification_model.program_step) -> String.equal s.src_state state) steps in
  let* transition_lines = concat_map_result (emit_transition env 2) state_steps in
  Ok (line 1 ("case " ^ control_state_ctor env.node state ^ ":") :: transition_lines @ [ line 2 "break;" ])

let emit_step_function program_env node =
  let env = node_env program_env node in
  let output_temps =
    List.map
      (fun (v : vdecl) ->
        line 1
          (c_type_name v.vty ^ " " ^ output_tmp_name v ^ " = state->" ^ field_name v ^ ";"))
      node.outputs
  in
  let* case_lines = concat_map_result (emit_state_case env node.steps) node.states in
  let output_commits =
    List.concat_map
      (fun (v : vdecl) ->
        [
          line 1 ("state->" ^ field_name v ^ " = " ^ output_tmp_name v ^ ";");
          line 1 ("*" ^ output_pointer_name v ^ " = " ^ output_tmp_name v ^ ";");
        ])
      node.outputs
  in
  Ok
    ([
       "void " ^ step_function_name node ^ "(" ^ String.concat ", " (step_params node) ^ ") {";
     ]
    @ output_temps
    @ [ line 1 "switch (state->control_state) {" ]
    @ case_lines
    @ [ line 1 "default:"; line 2 "break;"; line 1 "}" ]
    @ output_commits @ [ "}" ])

let dedup_by key xs =
  let seen = Hashtbl.create 16 in
  xs
  |> List.filter (fun x ->
         let k = key x in
         if Hashtbl.mem seen k then false
         else (
           Hashtbl.add seen k ();
           true))

let collect_type_decls program =
  program
  |> List.concat_map (fun (n : Verification_model.node_model) -> n.type_decls)
  |> dedup_by (fun (decl : enum_decl) -> decl.enum_name)

let collect_function_decls program =
  program
  |> List.concat_map (fun (n : Verification_model.node_model) -> n.function_decls)
  |> dedup_by (fun (decl : pure_function_decl) -> decl.function_name)

let rec expr_function_calls acc (e : expr) =
  match e.expr with
  | ELitInt _ | ELitBool _ | ELitEnum _ | EVar _ -> acc
  | EFunCall (fn, args) ->
      List.fold_left expr_function_calls (StringSet.add fn acc) args
  | EBin (_, left, right) | ECmp (_, left, right) ->
      expr_function_calls (expr_function_calls acc left) right
  | EUn (_, inner) -> expr_function_calls acc inner

let rec hexpr_function_calls acc (h : hexpr) =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> acc
  | HPred (_, args) ->
      List.fold_left hexpr_function_calls acc args
  | HFunCall (fn, args) ->
      List.fold_left hexpr_function_calls (StringSet.add fn acc) args
  | HBin (_, left, right) | HCmp (_, left, right) ->
      hexpr_function_calls (hexpr_function_calls acc left) right
  | HUn (_, inner) -> hexpr_function_calls acc inner

let rec stmt_function_calls acc (s : stmt) =
  match s.stmt with
  | SAssign (_, rhs) -> expr_function_calls acc rhs
  | SAssert formula -> hexpr_function_calls acc formula
  | SIf (cond, then_stmts, else_stmts) ->
      let acc = expr_function_calls acc cond in
      let acc = List.fold_left stmt_function_calls acc then_stmts in
      List.fold_left stmt_function_calls acc else_stmts
  | SWhile (cond, _invariants, _variant, body) ->
      let acc = expr_function_calls acc cond in
      List.fold_left stmt_function_calls acc body
  | SMatch (scrutinee, branches, default_branch) ->
      let acc = expr_function_calls acc scrutinee in
      let acc =
        List.fold_left
          (fun acc (_, stmts) -> List.fold_left stmt_function_calls acc stmts)
          acc branches
      in
      List.fold_left stmt_function_calls acc default_branch
  | SSkip -> acc
  | SCall (_, args, _) -> List.fold_left expr_function_calls acc args

let step_function_calls acc (step : Verification_model.program_step) =
  let acc =
    match step.guard_expr with
    | None -> acc
    | Some guard -> expr_function_calls acc guard
  in
  let acc = List.fold_left stmt_function_calls acc step.body_stmts in
  acc

let executable_function_names program all_functions =
  let by_name = Hashtbl.create (List.length all_functions) in
  List.iter
    (fun (f : pure_function_decl) -> Hashtbl.replace by_name f.function_name f)
    all_functions;
  let initial =
    List.fold_left
      (fun acc (node : Verification_model.node_model) ->
        List.fold_left step_function_calls acc node.steps)
      StringSet.empty program
  in
  let rec close seen work =
    match work with
    | [] -> seen
    | name :: rest ->
        if StringSet.mem name seen then close seen rest
        else
          let seen = StringSet.add name seen in
          let body_calls =
            match Hashtbl.find_opt by_name name with
            | None -> StringSet.empty
            | Some f -> expr_function_calls StringSet.empty f.function_body
          in
          close seen (StringSet.elements body_calls @ rest)
  in
  close StringSet.empty (StringSet.elements initial)

let collect_executable_function_decls program =
  let all_functions = collect_function_decls program in
  let executable_names = executable_function_names program all_functions in
  List.filter
    (fun (f : pure_function_decl) -> StringSet.mem f.function_name executable_names)
    all_functions

let program_env type_decls =
  let enum_ctor_types = Hashtbl.create 32 in
  List.iter
    (fun (decl : enum_decl) ->
      List.iter
        (fun ctor ->
          if Hashtbl.mem enum_ctor_types ctor then ()
          else Hashtbl.add enum_ctor_types ctor decl.enum_name)
        decl.enum_constructors)
    type_decls;
  { enum_ctor_types }

let header_guard_of_name header_name =
  "KAIROS_" ^ upper_ident header_name ^ "_"

let emit_header ~header_name program =
  let type_decls = collect_type_decls program in
  let guard = header_guard_of_name header_name in
  let type_lines = List.concat_map emit_enum_decl type_decls in
  let node_lines =
    program
    |> List.concat_map (fun node -> emit_node_header node @ [ blank ])
  in
  join_lines
    ([
       "#ifndef " ^ guard;
       "#define " ^ guard;
       blank;
       "#include <stdbool.h>";
       blank;
       "#ifdef __cplusplus";
       "extern \"C\" {";
       "#endif";
       blank;
     ]
    @ type_lines @ (if type_lines = [] then [] else [ blank ])
    @ node_lines
    @ [
        "#ifdef __cplusplus";
        "}";
        "#endif";
        blank;
        "#endif";
      ])

let emit_source ~header_name program =
  let type_decls = collect_type_decls program in
  let function_decls = collect_executable_function_decls program in
  let env = program_env type_decls in
  let prototypes = List.map emit_function_prototype function_decls in
  let* function_blocks = map_result (emit_function_definition env) function_decls in
  let* step_blocks = map_result (emit_step_function env) program in
  let init_blocks = List.map emit_init_function program in
  let function_lines =
    prototypes @ (if prototypes = [] then [] else [ blank ])
    @ List.concat_map (fun lines -> lines @ [ blank ]) function_blocks
  in
  let node_lines =
    List.concat_map (fun lines -> lines @ [ blank ]) init_blocks
    @ List.concat_map (fun lines -> lines @ [ blank ]) step_blocks
  in
  Ok
    (join_lines
       ([
          "#include \"" ^ header_name ^ "\"";
          "#include <assert.h>";
          blank;
        ]
       @ function_lines @ node_lines))

let emit_program ?(header_name = "kairos_generated.h") program =
  let* source = emit_source ~header_name program in
  let header = emit_header ~header_name program in
  let source_name =
    if Filename.check_suffix header_name ".h" then
      Filename.chop_suffix header_name ".h" ^ ".c"
    else header_name ^ ".c"
  in
  Ok
    [
      { file_name = header_name; contents = header };
      { file_name = source_name; contents = source };
    ]
