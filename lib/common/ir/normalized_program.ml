open Ast

type contract_formula = {
  value : ltl;
  origin : Formula_origin.t option;
  oid : int;
  loc : loc option;
}
[@@deriving yojson]

type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : contract_formula list;
  ensures : contract_formula list;
  body : stmt list;
  uid : int option;
  warnings : string list;
}

type node_semantics = Ast.node_semantics
type node_specification = Ast.node_specification

type node = {
  semantics : node_semantics;
  specification : node_specification;
  trans : transition list;
  uid : int option;
  user_invariants : invariant_user list;
  coherency_goals : contract_formula list;
}

let of_ast_contract_formula ?origin (f : Ast.ltl_o) : contract_formula =
  { value = f.value; origin; oid = f.oid; loc = f.loc }

let to_ast_contract_formula (f : contract_formula) : Ast.ltl_o =
  { value = f.value; oid = f.oid; loc = f.loc }

let of_ast_transition (t : Ast.transition) : transition =
  {
    src = t.src;
    dst = t.dst;
    guard = t.guard;
    requires = [];
    ensures = [];
    body = t.body;
    uid = None;
    warnings = [];
  }

let to_ast_transition (t : transition) : Ast.transition =
  { src = t.src; dst = t.dst; guard = t.guard; body = t.body }

let of_ast_node (n : Ast.node) : node =
  let semantics = Ast.semantics_of_node n in
  let spec = Ast.specification_of_node n in
  {
    semantics;
    specification = spec;
    trans = List.map of_ast_transition n.semantics.sem_trans;
    uid = None;
    user_invariants = [];
    coherency_goals = [];
  }

let to_ast_node (n : node) : Ast.node =
  {
    semantics =
      {
        n.semantics with
        sem_trans = List.map to_ast_transition n.trans;
      };
    specification = n.specification;
  }

let map_transitions (f : transition list -> transition list) (n : node) : node =
  { n with trans = f n.trans }

let with_origin ?loc origin value : contract_formula =
  { value; origin = Some origin; oid = Provenance.fresh_id (); loc }

let map_formula f (x : contract_formula) : contract_formula = { x with value = f x.value }
let values xs = List.map (fun x -> x.value) xs

let indent_str (n : int) : string = String.make (2 * max 0 n) ' '

let render_origin = function
  | None -> ""
  | Some o ->
      let s =
        match o with
        | Formula_origin.UserContract -> "UserContract"
        | Formula_origin.Instrumentation -> "Instrumentation"
        | Formula_origin.Coherency -> "Coherency"
        | Formula_origin.Compatibility -> "Compatibility"
        | Formula_origin.AssumeAutomaton -> "AssumeAutomaton"
        | Formula_origin.Internal -> "Internal"
      in
      " {" ^ s ^ "}"

let render_fo_o (kw : string) (f : contract_formula) (indent_level : int) : string =
  indent_str indent_level ^ kw ^ " " ^ Support.string_of_ltl f.value ^ render_origin f.origin ^ ";"

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
  (* Keep the abstract OBC+ view focused on contracts + transition code.
     Internal instrumentation statements are intentionally hidden here. *)
  let sections =
    reqs @ ens
    @
    if body = [] then [] else (indent_str (indent + 1) ^ "do") :: body
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
  let sem = n.semantics in
  let spec = n.specification in
  let line_params name vs =
    if vs = [] then None
    else Some (name ^ " " ^ String.concat ", " (List.map render_vdecl vs) ^ ";")
  in
  let line_states =
    if sem.sem_states = [] then None else Some ("states " ^ String.concat ", " sem.sem_states ^ ";")
  in
  let line_init = Some ("init " ^ sem.sem_init_state ^ ";") in
  let line_assumes =
    if spec.spec_assumes = [] then []
    else
      List.map (fun a -> "assume " ^ Support.string_of_ltl a ^ ";") spec.spec_assumes
  in
  let line_guarantees =
    if spec.spec_guarantees = [] then []
    else
      List.map (fun g -> "guarantee " ^ Support.string_of_ltl g ^ ";") spec.spec_guarantees
  in
  let fields =
    [
      line_params "inputs" sem.sem_inputs;
      line_params "outputs" sem.sem_outputs;
      line_params "locals" sem.sem_locals;
      line_states;
      line_init;
    ]
    |> List.filter_map (fun x -> x)
  in
  let trans = List.map (render_transition ~indent:1) n.trans in
let body =
    List.map (fun l -> indent_str 1 ^ l) (fields @ line_assumes @ line_guarantees)
    @ trans
  in
  String.concat "\n" ([ "node " ^ sem.sem_nname ^ " {" ] @ body @ [ "}" ])

let render_program (p : node list) : string = String.concat "\n\n" (List.map render_node p)
