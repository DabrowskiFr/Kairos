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

type import_decl = {
  import_path : string;
  import_loc : Loc.loc option;
}

type source = {
  imports : import_decl list;
  nodes : Ast.program;
}

let imported_paths (parsed_source : source) : string list =
  List.map (fun decl -> decl.import_path) parsed_source.imports

type parse_error = {
  loc : Loc.loc option;
  message : string;
}

type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

let lower_loc (loc : Kx_loc.loc) : Loc.loc =
  {
    line = loc.line;
    col = loc.col;
    line_end = loc.line_end;
    col_end = loc.col_end;
  }

let lower_ty (ty : Kx_core_syntax.ty) : Core_syntax.ty =
  match ty with
  | Kx_core_syntax.TInt -> Core_syntax.TInt
  | Kx_core_syntax.TBool -> Core_syntax.TBool
  | Kx_core_syntax.TReal -> Core_syntax.TReal
  | Kx_core_syntax.TCustom name -> Core_syntax.TCustom name

let lower_binop (op : Kx_core_syntax.binop) : Core_syntax.binop =
  match op with
  | Kx_core_syntax.Add -> Core_syntax.Add
  | Kx_core_syntax.Sub -> Core_syntax.Sub
  | Kx_core_syntax.Mul -> Core_syntax.Mul
  | Kx_core_syntax.Div -> Core_syntax.Div
  | Kx_core_syntax.And -> Core_syntax.And
  | Kx_core_syntax.Or -> Core_syntax.Or

let lower_unop (op : Kx_core_syntax.unop) : Core_syntax.unop =
  match op with
  | Kx_core_syntax.Neg -> Core_syntax.Neg
  | Kx_core_syntax.Not -> Core_syntax.Not

let lower_relop (op : Kx_core_syntax.relop) : Core_syntax.relop =
  match op with
  | Kx_core_syntax.REq -> Core_syntax.REq
  | Kx_core_syntax.RNeq -> Core_syntax.RNeq
  | Kx_core_syntax.RLt -> Core_syntax.RLt
  | Kx_core_syntax.RLe -> Core_syntax.RLe
  | Kx_core_syntax.RGt -> Core_syntax.RGt
  | Kx_core_syntax.RGe -> Core_syntax.RGe

let rec lower_expr (e : Kx_core_syntax.expr) : Core_syntax.expr =
  let expr =
    match e.expr with
    | Kx_core_syntax.ELitInt n -> Core_syntax.ELitInt n
    | Kx_core_syntax.ELitBool b -> Core_syntax.ELitBool b
    | Kx_core_syntax.EVar v -> Core_syntax.EVar v
    | Kx_core_syntax.EBin (op, a, b) ->
        Core_syntax.EBin (lower_binop op, lower_expr a, lower_expr b)
    | Kx_core_syntax.ECmp (op, a, b) ->
        Core_syntax.ECmp (lower_relop op, lower_expr a, lower_expr b)
    | Kx_core_syntax.EUn (op, inner) -> Core_syntax.EUn (lower_unop op, lower_expr inner)
  in
  { Core_syntax.expr; loc = Option.map lower_loc e.loc }

let rec lower_hexpr (h : Kx_core_syntax.hexpr) : Core_syntax.hexpr =
  let hexpr =
    match h.hexpr with
    | Kx_core_syntax.HLitInt n -> Core_syntax.HLitInt n
    | Kx_core_syntax.HLitBool b -> Core_syntax.HLitBool b
    | Kx_core_syntax.HVar v -> Core_syntax.HVar v
    | Kx_core_syntax.HPreK (v, k) -> Core_syntax.HPreK (v, k)
    | Kx_core_syntax.HPred (id, hs) -> Core_syntax.HPred (id, List.map lower_hexpr hs)
    | Kx_core_syntax.HBin (op, a, b) ->
        Core_syntax.HBin (lower_binop op, lower_hexpr a, lower_hexpr b)
    | Kx_core_syntax.HCmp (op, a, b) ->
        Core_syntax.HCmp (lower_relop op, lower_hexpr a, lower_hexpr b)
    | Kx_core_syntax.HUn (op, inner) -> Core_syntax.HUn (lower_unop op, lower_hexpr inner)
  in
  { Core_syntax.hexpr; loc = Option.map lower_loc h.loc }

let rec lower_ltl (f : Kx_core_syntax.ltl) : Core_syntax.ltl =
  match f with
  | Kx_core_syntax.LTrue -> Core_syntax.LTrue
  | Kx_core_syntax.LFalse -> Core_syntax.LFalse
  | Kx_core_syntax.LAtom (h1, r, h2) ->
      Core_syntax.LAtom (lower_hexpr h1, lower_relop r, lower_hexpr h2)
  | Kx_core_syntax.LNot a -> Core_syntax.LNot (lower_ltl a)
  | Kx_core_syntax.LAnd (a, b) -> Core_syntax.LAnd (lower_ltl a, lower_ltl b)
  | Kx_core_syntax.LOr (a, b) -> Core_syntax.LOr (lower_ltl a, lower_ltl b)
  | Kx_core_syntax.LImp (a, b) -> Core_syntax.LImp (lower_ltl a, lower_ltl b)
  | Kx_core_syntax.LX a -> Core_syntax.LX (lower_ltl a)
  | Kx_core_syntax.LG a -> Core_syntax.LG (lower_ltl a)
  | Kx_core_syntax.LW (a, b) -> Core_syntax.LW (lower_ltl a, lower_ltl b)

let lower_vdecl (v : Kx_core_syntax.vdecl) : Core_syntax.vdecl =
  { vname = v.vname; vty = lower_ty v.vty }

let rec lower_stmt (s : Kx_ast.stmt) : Ast.stmt =
  let stmt =
    match s.stmt with
    | Kx_ast.SAssign (id, e) -> Ast.SAssign (id, lower_expr e)
    | Kx_ast.SIf (c, t, e) -> Ast.SIf (lower_expr c, List.map lower_stmt t, List.map lower_stmt e)
    | Kx_ast.SMatch (e, branches, dflt) ->
        Ast.SMatch
          ( lower_expr e,
            List.map (fun (ctor, body) -> (ctor, List.map lower_stmt body)) branches,
            List.map lower_stmt dflt )
    | Kx_ast.SSkip -> Ast.SSkip
    | Kx_ast.SCall (callee, args, outs) -> Ast.SCall (callee, List.map lower_expr args, outs)
  in
  { Ast.stmt; loc = Option.map lower_loc s.loc }

let lower_transition (t : Kx_ast.transition) : Ast.transition =
  {
    Ast.src = t.src;
    dst = t.dst;
    guard = Option.map lower_expr t.guard;
    body = List.map lower_stmt t.body;
  }

let lower_state_invariant (inv : Kx_ast.invariant_state_rel) : Ast.invariant_state_rel =
  { Ast.state = inv.state; formula = lower_hexpr inv.formula }

let lower_node (n : Kx_ast.node) : Ast.node =
  {
    Ast.semantics =
      {
        sem_nname = n.semantics.sem_nname;
        sem_inputs = List.map lower_vdecl n.semantics.sem_inputs;
        sem_outputs = List.map lower_vdecl n.semantics.sem_outputs;
        sem_instances = n.semantics.sem_instances;
        sem_locals = List.map lower_vdecl n.semantics.sem_locals;
        sem_states = n.semantics.sem_states;
        sem_init_state = n.semantics.sem_init_state;
        sem_trans = List.map lower_transition n.semantics.sem_trans;
      };
    specification =
      {
        spec_assumes = List.map lower_ltl n.specification.spec_assumes;
        spec_guarantees = List.map lower_ltl n.specification.spec_guarantees;
        spec_invariants_state_rel =
          List.map lower_state_invariant n.specification.spec_invariants_state_rel;
      };
  }

let parse_source_text_with_info ~(filename : string) ~(text : string) : source * parse_info =
  let file_text = text in
  let file_hash = Digest.to_hex (Digest.string file_text) in
  let lb = Sedlexing.Utf8.from_string file_text in
  Sedlexing.set_filename lb filename;
  try
    let last_two = ref [] in
    let start_pos = { Lexing.pos_fname = filename; pos_lnum = 1; pos_bol = 0; pos_cnum = 0 } in
    let module I = Kx_parser.MenhirInterpreter in
    let push_lexeme s =
      if s <> "" then
        last_two :=
          match !last_two with [] -> [ s ] | [ a ] -> [ a; s ] | [ _; b ] -> [ b; s ] | _ -> [ s ]
    in
    let supplier () =
      let tok = Kx_lexer.token lb in
      push_lexeme (Kx_lexer.last_lexeme ());
      let startp, endp = Sedlexing.lexing_positions lb in
      (tok, startp, endp)
    in
    let handle_error checkpoint_input _checkpoint_error =
      let pos, _ = Sedlexing.lexing_positions lb in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      let lexeme =
        let s = Kx_lexer.last_lexeme () in
        if s = "" then "<eof>" else s
      in
      let expected =
        let tokens =
          List.filter
            (fun (_name, tok) -> I.acceptable checkpoint_input tok pos)
            Kx_lexer.expected_tokens
          |> List.map fst
        in
        if tokens = [] then "" else " Expected: " ^ String.concat ", " tokens
      in
      let context =
        match !last_two with
        | [ a; b ] -> Printf.sprintf " after '%s' before '%s'" a b
        | [ a ] -> Printf.sprintf " after '%s'" a
        | _ -> ""
      in
      raise
        (Failure
           (Printf.sprintf "Parse error at %s:%d:%d near '%s'%s.%s" pos.pos_fname pos.pos_lnum col
              lexeme context expected))
    in
    let checkpoint = Kx_parser.Incremental.source_file start_pos in
    let imports_raw, nodes_kx =
      I.loop_handle_undo (fun v -> v) handle_error supplier checkpoint
    in
    let imports =
      List.map
        (fun (import_path, import_loc) ->
          { import_path; import_loc = Option.map lower_loc import_loc })
        imports_raw
    in
    let parsed_source = { imports; nodes = List.map lower_node nodes_kx } in
    let info =
      {
        source_path = Some filename;
        text_hash = Some file_hash;
        parse_errors = [];
        warnings = [];
      }
    in
    (parsed_source, info)
  with
  | Kx_lexer.Lexing_error msg ->
      let pos, _ = Sedlexing.lexing_positions lb in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      raise
        (Failure
           (Printf.sprintf "Lexing error at %s:%d:%d: %s" pos.pos_fname pos.pos_lnum col msg))
  | e ->
      let pos, _ = Sedlexing.lexing_positions lb in
      Printf.eprintf "Parse error at %s:%d:%d\n" pos.pos_fname pos.pos_lnum
        (pos.pos_cnum - pos.pos_bol);
      raise e
