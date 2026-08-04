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

type ident = Kr_domain_core_syntax.ident
type loc = Kr_domain_core_locations.loc
type ltl = Kr_domain_core_syntax.ltl
type ltl_o = Kr_domain_core_syntax.ltl_o
type 'phase hexpr = 'phase Kr_domain_core_syntax.hexpr
type expr = Kr_domain_core_syntax.expr
type stmt = Kr_domain_core_syntax.stmt
type vdecl = Kr_domain_core_syntax.vdecl

type formula_id = int
type transition_index = int
type automaton_state_index = int
