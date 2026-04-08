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

let json_vdecl_of_ast (v : Ast.vdecl) : Yojson.Safe.t =
  let ty =
    match v.vty with
    | Ast.TInt -> "int"
    | Ast.TBool -> "bool"
    | Ast.TReal -> "real"
    | Ast.TCustom s -> s
  in
  `Assoc [ ("name", `String v.vname); ("type", `String ty) ]

let rec json_stmt_of_ast (s : Ast.stmt) : Yojson.Safe.t =
  let desc =
    match s.stmt with
    | Ast.SAssign (name, expr) ->
        `Assoc
          [
            ("kind", `String "assign");
            ("lhs", `String name);
            ("rhs", `String (Logic_pretty.string_of_iexpr expr));
          ]
    | Ast.SIf (cond, then_branch, else_branch) ->
        `Assoc
          [
            ("kind", `String "if");
            ("cond", `String (Logic_pretty.string_of_iexpr cond));
            ("then", `List (List.map json_stmt_of_ast then_branch));
            ("else", `List (List.map json_stmt_of_ast else_branch));
          ]
    | Ast.SMatch (expr, branches, default) ->
        `Assoc
          [
            ("kind", `String "match");
            ("expr", `String (Logic_pretty.string_of_iexpr expr));
            ( "branches",
              `List
                (List.map
                   (fun (ctor, body) ->
                     `Assoc
                       [ ("ctor", `String ctor); ("body", `List (List.map json_stmt_of_ast body)) ])
                   branches) );
            ("default", `List (List.map json_stmt_of_ast default));
          ]
    | Ast.SSkip -> `Assoc [ ("kind", `String "skip") ]
    | Ast.SCall (inst, args, outs) ->
        `Assoc
          [
            ("kind", `String "call");
            ("instance", `String inst);
            ("args", `List (List.map (fun e -> `String (Logic_pretty.string_of_iexpr e)) args));
            ("outs", `List (List.map (fun x -> `String x) outs));
          ]
  in
  match s.loc with
  | None -> desc
  | Some loc ->
      `Assoc
        [
          ("loc", `String (Ast_queries.loc_to_string loc));
          ("stmt", desc);
        ]

let json_transition_of_ast (t : Ast.transition) : Yojson.Safe.t =
  `Assoc
    [
      ("src", `String t.src);
      ("dst", `String t.dst);
      ( "guard",
        match t.guard with
        | None -> `Null
        | Some g -> `String (Logic_pretty.string_of_iexpr g) );
      ("body", `List (List.map json_stmt_of_ast t.body));
    ]

let json_node_of_ast (n : Ast.node) : Yojson.Safe.t =
  let sem = n.semantics in
  let spec = Ast.specification_of_node n in
  `Assoc
    [
      ("name", `String sem.sem_nname);
      ("inputs", `List (List.map json_vdecl_of_ast sem.sem_inputs));
      ("outputs", `List (List.map json_vdecl_of_ast sem.sem_outputs));
      ("locals", `List (List.map json_vdecl_of_ast sem.sem_locals));
      ("states", `List (List.map (fun s -> `String s) sem.sem_states));
      ("init_state", `String sem.sem_init_state);
      ( "instances",
        `List
          (List.map
             (fun (inst, node) -> `List [ `String inst; `String node ])
             sem.sem_instances) );
      ("assumes", `List (List.map (fun f -> `String (Logic_pretty.string_of_ltl f)) spec.spec_assumes));
      ("guarantees", `List (List.map (fun f -> `String (Logic_pretty.string_of_ltl f)) spec.spec_guarantees));
      ("transitions", `List (List.map json_transition_of_ast sem.sem_trans));
    ]

let write_json ~(out : string option) (json : Yojson.Safe.t) : unit =
  let payload = Yojson.Safe.to_string json in
  match out with
  | None -> print_endline payload
  | Some path ->
      let oc = open_out path in
      output_string oc payload;
      output_char oc '\n';
      close_out oc

let dump_program_json ~(out : string option) (p : Ast.program) : unit =
  write_json ~out (`Assoc [ ("program", `String (Ast.show_program p)) ])

let dump_program_json_stable ~(out : string option) (p : Ast.program) : unit =
  write_json ~out (`Assoc [ ("nodes", `List (List.map json_node_of_ast p)) ])
