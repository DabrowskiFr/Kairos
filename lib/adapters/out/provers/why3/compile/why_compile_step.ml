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

[@@@ocaml.warning "-8"]

open Why3
open Ptree
open Core_syntax
open Why_compile_expr
open Why_compile_ptree_helpers

let explicit_noop () =
  let noop = ident "__noop" in
  mk_expr
    (Elet
       ( noop,
         false,
         Expr.RKnone,
         mk_expr (Econst (Constant.int_const (Why3.BigInt.of_int 0))),
         mk_expr (Etuple []) ))

let rec compile_seq (env : env) (lst : Core_syntax.stmt list) : Ptree.expr =
  let compile_assignment x rhs =
    if is_rec_var env x then begin
      note_input env env.rec_name;
      mk_expr
        (Eassign
           [
             ( mk_expr (Eident (qid1 env.rec_name)),
               Some (qid1 x),
               rhs );
           ])
    end
    else if is_ref_var env x then begin
      note_input env x;
      mk_expr
        (Eassign
           [
             ( mk_expr (Eident (qid1 x)),
               Some (qid1 "contents"),
               rhs );
           ])
    end else begin
      note_input env x;
      mk_expr (Eassign [ (mk_expr (Eident (qid1 x)), None, rhs) ])
    end
  in
  let compile_stmt (stmt : Core_syntax.stmt) : Ptree.expr =
    match stmt.stmt with
    | SSkip -> mk_expr (Etuple [])
    | SAssign (x, e) ->
        compile_assignment x (compile_expr env e)
    | SAssert formula ->
        mk_expr (Eassert (Expr.Assert, compile_hexpr env formula))
    | SIf (c, tbr, fbr) ->
        let cond = compile_expr env c in
        begin
          match (tbr, fbr) with
          | ( [ { stmt = SAssign (x_then, e_then); _ } ],
              [ { stmt = SAssign (x_else, e_else); _ } ] )
            when String.equal x_then x_else ->
              let rhs =
                mk_expr
                  (Eif
                     ( cond,
                       compile_expr env e_then,
                       compile_expr env e_else ))
              in
              compile_assignment x_then rhs
          | _ ->
              let else_branch =
                if fbr = [] then explicit_noop () else compile_seq env fbr
              in
              mk_expr (Eif (cond, compile_seq env tbr, else_branch))
        end
    | SWhile (cond, invariants, variant, body) ->
        let invariants =
          List.map (compile_hexpr env) invariants
        in
        let variant =
          match variant with
          | None -> []
          | Some term -> [ (compile_term env term, None) ]
        in
        mk_expr
          (Ewhile
             ( compile_expr env cond,
               invariants,
               variant,
               compile_seq env body ))
    | SMatch (e, branches, default) ->
        let scrut = compile_expr env e in
        let branches =
          List.map
            (fun (ctor, body) ->
              let pat = { pat_desc = Papp (qid1 ctor, []); pat_loc = loc } in
              (pat, compile_seq env body))
            branches
        in
        let branches =
          if default = [] then branches
          else
            branches @ [ ({ pat_desc = Pwild; pat_loc = loc }, compile_seq env default) ]
        in
        mk_expr (Ematch (scrut, branches, []))
    | SCall _ -> failwith "instance calls are not supported"
    | SMethodCall (callee, args) ->
        let decl =
          match
            List.find_opt
              (fun (decl : method_decl) ->
                String.equal decl.method_name callee)
              env.methods
          with
          | Some decl -> decl
          | None -> failwith (Printf.sprintf "unknown method '%s'" callee)
        in
        let bindings = ref [] in
        let temp_for name =
          match List.assoc_opt name !bindings with
          | Some temp -> temp
          | None ->
              let temp =
                Printf.sprintf "__method_inout_%d" (List.length !bindings)
              in
              bindings := (name, temp) :: !bindings;
              temp
        in
        let explicit_args =
          List.map2
            (fun (param : method_param) arg ->
              match param.method_param_mode with
              | MPIn -> compile_expr env arg
              | MPInOut -> (
                  match arg.expr with
                  | EVar name when is_ref_var env name ->
                      mk_expr (Eident (qid1 name))
                  | EVar name when is_rec_var env name ->
                      mk_expr (Eident (qid1 (temp_for name)))
                  | EVar name ->
                      failwith
                        (Printf.sprintf
                           "inout method argument '%s' is not writable" name)
                  | _ ->
                      failwith
                        (Printf.sprintf
                           "inout parameter '%s' of method '%s' requires a variable"
                           param.method_param_name callee)))
            decl.method_params args
        in
        let implicit_args =
          mk_expr (Eident (qid1 env.rec_name))
          :: List.map
               (fun (input : vdecl) ->
                 compile_expr env
                   (Core_syntax_builders.mk_expr (EVar input.vname)))
               env.input_vars
        in
        let call =
          apply_expr (mk_expr (Eident (qid1 callee)))
            (implicit_args @ explicit_args)
        in
        let commits =
          List.rev_map
            (fun (name, temp) ->
              compile_assignment name (ref_contents_expr temp))
            !bindings
        in
        let body = seq_exprs (call :: commits) in
        List.fold_left
          (fun body (name, temp) ->
            let initial =
              mk_expr
                (Eidapp
                   ( qid1 "ref",
                     [
                       compile_expr env
                         (Core_syntax_builders.mk_expr (EVar name));
                     ] ))
            in
            mk_expr (Elet (ident temp, false, Expr.RKnone, initial, body)))
          body !bindings
  in
  match lst with
  | [] -> mk_expr (Etuple [])
  | [ stmt ] -> compile_stmt stmt
  | stmt :: rest ->
      mk_expr
        (Esequence
           (compile_stmt stmt, compile_seq env rest))

let compile_transition_body (env : env) (t : Ir.transition) : Ptree.expr =
  note_input env env.rec_name;
  let assign_dst =
    mk_expr
      (Eassign
         [
           ( mk_expr (Eident (qid1 env.rec_name)),
             Some (qid1 "st"),
             mk_expr (Eident (qid1 t.dst_state)) );
         ])
  in
  seq_exprs [ compile_seq env t.body_stmts; assign_dst ]
