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

val formula_meta_to_yojson : Ir.formula_meta -> Yojson.Safe.t
val formula_meta_of_yojson : Yojson.Safe.t -> (Ir.formula_meta, string) result
val summary_formula_to_yojson : Ir.summary_formula -> Yojson.Safe.t
val summary_formula_of_yojson : Yojson.Safe.t -> (Ir.summary_formula, string) result
val summary_formula_list_to_yojson : Ir.summary_formula list -> Yojson.Safe.t
val summary_formula_list_of_yojson : Yojson.Safe.t -> (Ir.summary_formula list, string) result
