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

val string_of_qid : Why3.Ptree.qualid -> string
val string_of_const : Why3.Constant.constant -> string
val string_of_relop : Ast.relop -> string
val string_of_iexpr : ?ctx:int -> Ast.iexpr -> string
val string_of_hexpr : Ast.hexpr -> string
val string_of_fo_atom : ?ctx:int -> Ast.fo_atom -> string
val string_of_fo : ?ctx:int -> Fo_formula.t -> string
val string_of_ltl : ?ctx:int -> Ast.ltl -> string
