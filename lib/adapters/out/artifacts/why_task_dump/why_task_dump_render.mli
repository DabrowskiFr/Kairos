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

(** Why3/SMT textual dumps for artifact export.

    Dumps are produced per normalized Why3 task (one atomic VC obligation per
    item), so each emitted block maps to a single proof goal. *)

(** Dump normalized Why3 tasks as plain Why text.

    @param ptree
      WhyML parse tree to render.
    @return
      One textual task per normalized goal. *)
val dump_why3_tasks_of_ptree : ptree:Why3.Ptree.mlw_file -> string list

(** Dump normalized Why3 tasks with their Why3 attributes appended.

    @param ptree
      WhyML parse tree to render.
    @return
      One textual task per normalized goal, with additional attribute comments. *)
val dump_why3_tasks_with_attrs_of_ptree : ptree:Why3.Ptree.mlw_file -> string list

(** Dump normalized tasks as SMT-LIB2 scripts.

    @param ptree
      WhyML parse tree to render.
    @return
      One SMT-LIB2 script per normalized goal, prepared for Z3. *)
val dump_smt2_tasks_of_ptree : ptree:Why3.Ptree.mlw_file -> string list
