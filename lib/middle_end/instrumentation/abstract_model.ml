open Ast

type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : fo_o list;
  ensures : fo_o list;
  body : stmt list;
  attrs : transition_attrs;
}

type node = {
  nname : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  assumes : fo_ltl list;
  guarantees : fo_ltl list;
  instances : (ident * ident) list;
  locals : vdecl list;
  states : ident list;
  init_state : ident;
  trans : transition list;
  attrs : node_attrs;
}

let of_ast_transition (t : Ast.transition) : transition =
  {
    src = t.src;
    dst = t.dst;
    guard = t.guard;
    requires = t.requires;
    ensures = t.ensures;
    body = t.body;
    attrs = t.attrs;
  }

let to_ast_transition (t : transition) : Ast.transition =
  {
    src = t.src;
    dst = t.dst;
    guard = t.guard;
    requires = t.requires;
    ensures = t.ensures;
    body = t.body;
    attrs = t.attrs;
  }

let of_ast_node (n : Ast.node) : node =
  {
    nname = n.nname;
    inputs = n.inputs;
    outputs = n.outputs;
    assumes = n.assumes;
    guarantees = n.guarantees;
    instances = n.instances;
    locals = n.locals;
    states = n.states;
    init_state = n.init_state;
    trans = List.map of_ast_transition n.trans;
    attrs = n.attrs;
  }

let to_ast_node (n : node) : Ast.node =
  {
    nname = n.nname;
    inputs = n.inputs;
    outputs = n.outputs;
    assumes = n.assumes;
    guarantees = n.guarantees;
    instances = n.instances;
    locals = n.locals;
    states = n.states;
    init_state = n.init_state;
    trans = List.map to_ast_transition n.trans;
    attrs = n.attrs;
  }

let map_transitions (f : transition list -> transition list) (n : node) : node =
  { n with trans = f n.trans }

let indent_str (n : int) : string = String.make (2 * max 0 n) ' '

let render_origin = function
  | None -> ""
  | Some o ->
      let s =
        match o with
        | UserContract -> "UserContract"
        | Instrumentation -> "Instrumentation"
        | Coherency -> "Coherency"
        | Compatibility -> "Compatibility"
        | AssumeAutomaton -> "AssumeAutomaton"
        | Internal -> "Internal"
      in
      " {" ^ s ^ "}"

let render_fo_o (kw : string) (f : fo_o) (indent_level : int) : string =
  indent_str indent_level ^ kw ^ " " ^ Support.string_of_fo f.value ^ render_origin f.origin ^ ";"

let rec render_stmt (s : stmt) (indent_level : int) : string list =
  match s.stmt with
  | SAssign (id, e) -> [ indent_str indent_level ^ id ^ " := " ^ Support.string_of_iexpr e ^ ";" ]
  | SSkip -> [ indent_str indent_level ^ "skip;" ]
  | SCall (inst, args, outs) ->
      let args_s = String.concat ", " (List.map Support.string_of_iexpr args) in
      let outs_s = String.concat ", " outs in
      [ indent_str indent_level ^ "call " ^ inst ^ "(" ^ args_s ^ ") returns (" ^ outs_s ^ ");" ]
  | SIf (c, t, e) ->
      [ indent_str indent_level ^ "if " ^ Support.string_of_iexpr c ^ " then" ]
      @ List.concat_map (fun st -> render_stmt st (indent_level + 1)) t
      @ [ indent_str indent_level ^ "else" ]
      @ List.concat_map (fun st -> render_stmt st (indent_level + 1)) e
      @ [ indent_str indent_level ^ "end;" ]
  | SMatch (e, branches, dflt) ->
      [ indent_str indent_level ^ "match " ^ Support.string_of_iexpr e ^ " with" ]
      @ List.concat_map
          (fun (ctor, body) ->
            [ indent_str (indent_level + 1) ^ "| " ^ ctor ^ " ->" ]
            @ List.concat_map (fun st -> render_stmt st (indent_level + 2)) body)
          branches
      @
      if dflt = [] then [ indent_str indent_level ^ "end;" ]
      else
        [ indent_str (indent_level + 1) ^ "| _ ->" ]
        @ List.concat_map (fun st -> render_stmt st (indent_level + 2)) dflt
        @ [ indent_str indent_level ^ "end;" ]

let render_transition ?(indent : int = 0) (t : transition) : string =
  let guard_s =
    match t.guard with None -> "" | Some g -> " when " ^ Support.string_of_iexpr g
  in
  let header = indent_str indent ^ "transition " ^ t.src ^ " -> " ^ t.dst ^ guard_s ^ " {" in
  let reqs = List.map (fun f -> render_fo_o "require" f (indent + 1)) t.requires in
  let ens = List.map (fun f -> render_fo_o "ensure" f (indent + 1)) t.ensures in
  let body = List.concat_map (fun s -> render_stmt s (indent + 1)) t.body in
  let ghost = List.concat_map (fun s -> render_stmt s (indent + 1)) t.attrs.ghost in
  (* Keep the abstract OBC+ view focused on contracts + transition code.
     Internal instrumentation statements are intentionally hidden here. *)
  let sections =
    reqs @ ens
    @
    if body = [] then [] else (indent_str (indent + 1) ^ "do") :: body
    @
    if ghost = [] then [] else (indent_str (indent + 1) ^ "ghost") :: ghost
  in
  String.concat "\n" (header :: sections @ [ indent_str indent ^ "}" ])

let render_vdecl (v : vdecl) : string =
  let ty_s =
    match v.vty with
    | TInt -> "int"
    | TBool -> "bool"
    | TReal -> "real"
    | TCustom s -> s
  in
  v.vname ^ ": " ^ ty_s

let render_node (n : node) : string =
  let line_params name vs =
    if vs = [] then None
    else Some (name ^ " " ^ String.concat ", " (List.map render_vdecl vs) ^ ";")
  in
  let line_states =
    if n.states = [] then None else Some ("states " ^ String.concat ", " n.states ^ ";")
  in
  let line_init = Some ("init " ^ n.init_state ^ ";") in
  let line_assumes =
    if n.assumes = [] then []
    else
      List.map (fun a -> "assume " ^ Support.string_of_ltl a ^ ";") n.assumes
  in
  let line_guarantees =
    if n.guarantees = [] then []
    else
      List.map (fun g -> "guarantee " ^ Support.string_of_ltl g ^ ";") n.guarantees
  in
  let fields =
    [ line_params "inputs" n.inputs; line_params "outputs" n.outputs; line_params "locals" n.locals; line_states; line_init ]
    |> List.filter_map (fun x -> x)
  in
  let trans = List.map (render_transition ~indent:1) n.trans in
  let body =
    List.map (fun l -> indent_str 1 ^ l) (fields @ line_assumes @ line_guarantees)
    @ trans
  in
  String.concat "\n" ([ "node " ^ n.nname ^ " {" ] @ body @ [ "}" ])

let render_program (p : node list) : string = String.concat "\n\n" (List.map render_node p)

type product_triple = int * int * int

let mk_triple i qa qg : product_triple = (i, qa, qg)
let prog_idx (i, _, _) = i
let assume_idx (_, qa, _) = qa
let guarantee_idx (_, _, qg) = qg
let is_bad_guarantee ~g_bad_idx t = g_bad_idx >= 0 && guarantee_idx t = g_bad_idx

type local_combo = {
  gp : fo;
  fg : fo;
  fa : fo;
  qa_src : int;
  qg_src : int;
  qa_dst : int;
  qg_dst : int;
}

let combo_formula (c : local_combo) : fo = FAnd (c.gp, FAnd (c.fg, c.fa))

let is_safe_successor ~a_bad_idx ~g_bad_idx (c : local_combo) : bool =
  not (a_bad_idx >= 0 && c.qa_dst = a_bad_idx) && not (g_bad_idx >= 0 && c.qg_dst = g_bad_idx)

let is_badg_successor ~a_bad_idx ~g_bad_idx (c : local_combo) : bool =
  not (a_bad_idx >= 0 && c.qa_dst = a_bad_idx) && g_bad_idx >= 0 && c.qg_dst = g_bad_idx

type transition_annotation = { req_hyp : fo_o list; ens_obl : fo_o list }

let empty_transition_annotation : transition_annotation = { req_hyp = []; ens_obl = [] }
