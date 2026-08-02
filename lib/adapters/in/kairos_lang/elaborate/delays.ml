(*--------------------------------------------------------------------------
 * Executable one-instant delays for observer expressions.
 *--------------------------------------------------------------------------*)

module S = Surface.Ast
module Names = Names
open S

type delay = {
  source : S.indexed_ref;
  source_name : string;
  cell_name : string;
  ty : Core.Syntax.ty;
}

let rec expr_pre_refs (expr : S.expr) =
  match expr.sexpr with
  | SELitInt _ | SELitBool _ | SEVar _ -> []
  | SEPre source -> [ source ]
  | SECall (_, args) -> List.concat_map expr_pre_refs args
  | SEBin (_, left, right) | SECmp (_, left, right) ->
      expr_pre_refs left @ expr_pre_refs right
  | SEUn (_, inner) -> expr_pre_refs inner

let rec stmt_pre_refs (stmt : S.stmt) =
  match stmt.sstmt with
  | SSAssign (_, rhs) -> expr_pre_refs rhs
  | SSIf (condition, then_branch, else_branch) ->
      expr_pre_refs condition
      @ List.concat_map stmt_pre_refs (then_branch @ else_branch)
  | SSWhile (condition, _, variant, body) ->
      expr_pre_refs condition
      @ Option.fold ~none:[] ~some:expr_pre_refs variant
      @ List.concat_map stmt_pre_refs body
  | SSMatch (scrutinee, branches, default_branch) ->
      expr_pre_refs scrutinee
      @ List.concat_map stmt_pre_refs
          (List.concat_map snd branches @ Option.value ~default:[] default_branch)
  | SSMethodCall (_, args) -> List.concat_map expr_pre_refs args
  | SSFor (_, _, body) | SSForRange (_, _, _, body) ->
      List.concat_map stmt_pre_refs body
  | SSSkip -> []

let collect env observers =
  let refs =
    observers
    |> List.concat_map (fun (observer : S.observer_decl) ->
           List.concat_map stmt_pre_refs observer.observer_step)
  in
  let seen = Hashtbl.create 16 in
  refs
  |> List.filter_map (fun source ->
         let source_name = Names.indexed_ref_name source in
         if Hashtbl.mem seen source_name then None
         else begin
           Hashtbl.add seen source_name ();
           match List.assoc_opt source_name env.Env.variables with
           | None ->
               Shared.Error.elaboration
                 (Printf.sprintf
                    "observer historical read pre(%s) refers to an unknown variable"
                    source_name)
           | Some ty ->
               Some
                 {
                   source;
                   source_name;
                   cell_name = Names.generated_delay_name source;
                   ty;
                 }
         end)

let ghosts delays =
  List.map
    (fun delay : S.raw_vdecl ->
      {
        raw_vname = delay.cell_name;
        raw_indices = None;
        raw_vty = delay.ty;
      })
    delays

let delay_for_ref delays reference =
  let name = Names.indexed_ref_name reference in
  List.find_opt (fun delay -> String.equal delay.source_name name) delays

let rec rewrite_expr delays (expr : S.expr) =
  let sexpr =
    match expr.sexpr with
    | SELitInt _ | SELitBool _ | SEVar _ -> expr.sexpr
    | SEPre source -> begin
        match delay_for_ref delays source with
        | Some delay -> SEVar (S.mk_scalar_ref delay.cell_name)
        | None ->
            Shared.Error.elaboration
              (Printf.sprintf
                 "internal error: no delay cell for pre(%s)"
                 (Names.indexed_ref_name source))
      end
    | SECall (name, args) -> SECall (name, List.map (rewrite_expr delays) args)
    | SEBin (op, left, right) ->
        SEBin (op, rewrite_expr delays left, rewrite_expr delays right)
    | SECmp (op, left, right) ->
        SECmp (op, rewrite_expr delays left, rewrite_expr delays right)
    | SEUn (op, inner) -> SEUn (op, rewrite_expr delays inner)
  in
  { expr with sexpr }

let rec rewrite_stmt delays (stmt : S.stmt) =
  let rewrite_list = List.map (rewrite_stmt delays) in
  let sstmt =
    match stmt.sstmt with
    | SSAssign (target, rhs) -> SSAssign (target, rewrite_expr delays rhs)
    | SSIf (condition, then_branch, else_branch) ->
        SSIf
          ( rewrite_expr delays condition,
            rewrite_list then_branch,
            rewrite_list else_branch )
    | SSWhile (condition, invariants, variant, body) ->
        SSWhile
          ( rewrite_expr delays condition,
            invariants,
            Option.map (rewrite_expr delays) variant,
            rewrite_list body )
    | SSMatch (scrutinee, branches, default_branch) ->
        SSMatch
          ( rewrite_expr delays scrutinee,
            List.map (fun (ctor, body) -> (ctor, rewrite_list body)) branches,
            Option.map rewrite_list default_branch )
    | SSMethodCall (name, args) ->
        SSMethodCall (name, List.map (rewrite_expr delays) args)
    | SSFor (name, enum_name, body) -> SSFor (name, enum_name, rewrite_list body)
    | SSForRange (name, lo, hi, body) ->
        SSForRange (name, lo, hi, rewrite_list body)
    | SSSkip -> SSSkip
  in
  { stmt with sstmt }

let rewrite_observers delays observers =
  List.map
    (fun (observer : S.observer_decl) ->
      {
        observer with
        observer_init = List.map (rewrite_stmt delays) observer.observer_init;
        observer_step = List.map (rewrite_stmt delays) observer.observer_step;
      })
    observers

let commit delay =
  S.mk_stmt
    (SSAssign
       ( S.mk_scalar_ref delay.cell_name,
         S.mk_expr (SEVar delay.source) ))

let append_commits delays (transition : S.transition) =
  { transition with body = transition.body @ List.map commit delays }

let state_invariants ~states ~init_state delays =
  let stable_states = List.filter (fun state -> not (String.equal state init_state)) states in
  List.concat_map
    (fun delay ->
      let left = S.mk_hexpr (SHVar (S.mk_scalar_ref delay.cell_name)) in
      let right = S.mk_hexpr (SHPreK (delay.source, SNNat 1)) in
      let formula = S.mk_hexpr (SHCmp (REq, left, right)) in
      List.map (fun state -> (state, formula)) stable_states)
    delays
