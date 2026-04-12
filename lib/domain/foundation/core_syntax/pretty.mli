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

val string_of_relop : Core_syntax.relop -> string
val string_of_expr : ?ctx:int -> Core_syntax.expr -> string
val string_of_hexpr : Core_syntax.hexpr -> string
val string_of_fo : ?ctx:int -> Core_syntax.hexpr -> string
val string_of_ltl : ?ctx:int -> Core_syntax.ltl -> string
