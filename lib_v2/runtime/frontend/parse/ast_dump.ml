let json_vdecl_of_ast (v : Ast.vdecl) : Yojson.Safe.t =
  let ty =
    match v.vty with
    | Ast.TInt -> "int"
    | Ast.TBool -> "bool"
    | Ast.TReal -> "real"
    | Ast.TCustom s -> s
  in
  `Assoc [ ("name", `String v.vname); ("type", `String ty) ]

let json_transition_of_ast (t : Ast.transition) : Yojson.Safe.t =
  `Assoc
    [
      ("src", `String t.src);
      ("dst", `String t.dst);
      ( "guard",
        match t.guard with
        | None -> `Null
        | Some g -> `String (Support.string_of_iexpr g) );
      ("requires", `List (List.map (fun f -> `String (Support.string_of_fo f.Ast.value)) t.requires));
      ("ensures", `List (List.map (fun f -> `String (Support.string_of_fo f.Ast.value)) t.ensures));
    ]

let json_node_of_ast (n : Ast.node) : Yojson.Safe.t =
  let spec = Ast.specification_of_node n in
  `Assoc
    [
      ("name", `String n.nname);
      ("inputs", `List (List.map json_vdecl_of_ast n.inputs));
      ("outputs", `List (List.map json_vdecl_of_ast n.outputs));
      ("locals", `List (List.map json_vdecl_of_ast n.locals));
      ("states", `List (List.map (fun s -> `String s) n.states));
      ("init_state", `String n.init_state);
      ( "instances",
        `List (List.map (fun (inst, node) -> `List [ `String inst; `String node ]) n.instances) );
      ("assumes", `List (List.map (fun f -> `String (Support.string_of_ltl f)) spec.spec_assumes));
      ("guarantees", `List (List.map (fun f -> `String (Support.string_of_ltl f)) spec.spec_guarantees));
      ("transitions", `List (List.map json_transition_of_ast n.trans));
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
  write_json ~out (`Assoc [ ("program", `String (Ast_utils.show_program p)) ])

let dump_program_json_stable ~(out : string option) (p : Ast.program) : unit =
  write_json ~out (`Assoc [ ("nodes", `List (List.map json_node_of_ast p)) ])
