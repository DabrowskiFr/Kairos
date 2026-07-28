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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

module C = Core_syntax
module Common = C_codegen_common
module Env = C_codegen_env
module Functions = C_codegen_functions
module Names = C_codegen_names
module Node = C_codegen_node
module Types = C_codegen_types

let ( let* ) = Common.( let* )

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
  |> dedup_by (fun (decl : C.enum_decl) -> decl.enum_name)

let collect_function_decls program =
  program
  |> List.concat_map (fun (n : Verification_model.node_model) -> n.function_decls)
  |> dedup_by (fun (decl : C.pure_function_decl) -> decl.function_name)

let rec expr_function_calls acc (e : C.expr) =
  match e.expr with
  | C.ELitInt _ | C.ELitBool _ | C.ELitEnum _ | C.EVar _ -> acc
  | C.EFunCall (fn, args) -> List.fold_left expr_function_calls (Common.StringSet.add fn acc) args
  | C.EBin (_, left, right) | C.ECmp (_, left, right) ->
      expr_function_calls (expr_function_calls acc left) right
  | C.EUn (_, inner) -> expr_function_calls acc inner

let rec hexpr_function_calls : type phase. Common.StringSet.t -> phase C.hexpr -> Common.StringSet.t
    =
 fun acc h ->
  match h.hexpr with
  | C.HLitInt _ | C.HLitBool _ | C.HLitEnum _ | C.HVar _ | C.HPreK _ -> acc
  | C.HPred (_, args) -> List.fold_left hexpr_function_calls acc args
  | C.HFunCall (fn, args) -> List.fold_left hexpr_function_calls (Common.StringSet.add fn acc) args
  | C.HBin (_, left, right) | C.HCmp (_, left, right) ->
      hexpr_function_calls (hexpr_function_calls acc left) right
  | C.HUn (_, inner) -> hexpr_function_calls acc inner

let rec stmt_function_calls acc (s : C.stmt) =
  match s.stmt with
  | C.SAssign (_, rhs) -> expr_function_calls acc rhs
  | C.SAssert formula -> hexpr_function_calls acc formula
  | C.SIf (cond, then_stmts, else_stmts) ->
      let acc = expr_function_calls acc cond in
      let acc = List.fold_left stmt_function_calls acc then_stmts in
      List.fold_left stmt_function_calls acc else_stmts
  | C.SWhile (cond, _invariants, _variant, body) ->
      let acc = expr_function_calls acc cond in
      List.fold_left stmt_function_calls acc body
  | C.SMatch (scrutinee, branches, default_branch) ->
      let acc = expr_function_calls acc scrutinee in
      let acc =
        List.fold_left
          (fun acc (_, stmts) -> List.fold_left stmt_function_calls acc stmts)
          acc branches
      in
      List.fold_left stmt_function_calls acc default_branch
  | C.SSkip -> acc
  | C.SCall (_, args, _) -> List.fold_left expr_function_calls acc args

let step_function_calls acc (step : Verification_model.program_step) =
  let acc =
    match step.guard_expr with None -> acc | Some guard -> expr_function_calls acc guard
  in
  let acc = List.fold_left stmt_function_calls acc step.body_stmts in
  acc

let executable_function_names program all_functions =
  let by_name = Hashtbl.create (List.length all_functions) in
  List.iter
    (fun (f : C.pure_function_decl) -> Hashtbl.replace by_name f.function_name f)
    all_functions;
  let initial =
    List.fold_left
      (fun acc (node : Verification_model.node_model) ->
        List.fold_left step_function_calls acc node.steps)
      Common.StringSet.empty program
  in
  let rec close seen work =
    match work with
    | [] -> seen
    | name :: rest ->
        if Common.StringSet.mem name seen then close seen rest
        else
          let seen = Common.StringSet.add name seen in
          let body_calls =
            match Hashtbl.find_opt by_name name with
            | None -> Common.StringSet.empty
            | Some f -> expr_function_calls Common.StringSet.empty f.function_body
          in
          close seen (Common.StringSet.elements body_calls @ rest)
  in
  close Common.StringSet.empty (Common.StringSet.elements initial)

let collect_executable_function_decls program =
  let all_functions = collect_function_decls program in
  let executable_names = executable_function_names program all_functions in
  List.filter
    (fun (f : C.pure_function_decl) -> Common.StringSet.mem f.function_name executable_names)
    all_functions

let emit_header ~header_name program =
  let type_decls = collect_type_decls program in
  let guard = Names.header_guard_of_name header_name in
  let type_lines = List.concat_map Node.emit_enum_decl type_decls in
  let node_lines =
    program |> List.concat_map (fun node -> Node.emit_node_header node @ [ Common.blank ])
  in
  Common.join_lines
    ([
       "#ifndef " ^ guard;
       "#define " ^ guard;
       Common.blank;
       "#include <stdbool.h>";
       Common.blank;
       "#ifdef __cplusplus";
       "extern \"C\" {";
       "#endif";
       Common.blank;
     ]
    @ type_lines
    @ (if type_lines = [] then [] else [ Common.blank ])
    @ node_lines
    @ [ "#ifdef __cplusplus"; "}"; "#endif"; Common.blank; "#endif" ])

let emit_source ~header_name program =
  let type_decls = collect_type_decls program in
  let function_decls = collect_executable_function_decls program in
  let env = Env.program_env type_decls in
  let prototypes = List.map Functions.emit_function_prototype function_decls in
  let* function_blocks =
    Common.map_result (Functions.emit_function_definition env) function_decls
  in
  let* step_blocks = Common.map_result (Node.emit_step_function env) program in
  let init_blocks = List.map Node.emit_init_function program in
  let function_lines =
    prototypes
    @ (if prototypes = [] then [] else [ Common.blank ])
    @ List.concat_map (fun lines -> lines @ [ Common.blank ]) function_blocks
  in
  let node_lines =
    List.concat_map (fun lines -> lines @ [ Common.blank ]) init_blocks
    @ List.concat_map (fun lines -> lines @ [ Common.blank ]) step_blocks
  in
  Ok
    (Common.join_lines
       ([ "#include \"" ^ header_name ^ "\""; "#include <assert.h>"; Common.blank ]
       @ function_lines @ node_lines))

let emit_program ?(header_name = "kairos_generated.h") program :
    (Types.generated_file list, string) result =
  let* source = emit_source ~header_name program in
  let header = emit_header ~header_name program in
  let source_name =
    if Filename.check_suffix header_name ".h" then Filename.chop_suffix header_name ".h" ^ ".c"
    else header_name ^ ".c"
  in
  Ok
    [
      { Types.file_name = header_name; contents = header };
      { Types.file_name = source_name; contents = source };
    ]
