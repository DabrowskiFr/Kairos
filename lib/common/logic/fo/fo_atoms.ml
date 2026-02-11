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

open Ast
open Ast_builders

type eq_value = VInt of int | VBool of bool
type eq_atom = { name : string; var : string; value : eq_value }

let extract_eq_atom ((f, name) : fo * ident) : eq_atom option =
  let mk var value = Some { name; var; value } in
  match f with
  | FRel (HNow a, REq, HNow b) -> begin
      match (as_var a, b.iexpr) with
      | Some x, ILitInt i -> mk x (VInt i)
      | Some x, ILitBool v -> mk x (VBool v)
      | _ -> begin
          match (as_var b, a.iexpr) with
          | Some x, ILitInt i -> mk x (VInt i)
          | Some x, ILitBool v -> mk x (VBool v)
          | _ -> None
        end
    end
  | _ -> None
