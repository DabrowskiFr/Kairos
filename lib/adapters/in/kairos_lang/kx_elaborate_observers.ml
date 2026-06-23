(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

module S = Kx_surface_syntax

let observer_raw_vdecl (obs : S.observer_decl) : S.raw_vdecl =
  { raw_vname = obs.observer_name; raw_indices = None; raw_vty = obs.observer_ty }

let observer_init_stmts (obs : S.observer_decl) = obs.observer_init

let observer_step_stmts (obs : S.observer_decl) = obs.observer_step

let observer_updates_for_transition ~(init_state : string) observers (t : S.transition) =
  let is_init_transition = String.equal t.src init_state in
  List.concat_map
    (fun obs -> if is_init_transition then observer_init_stmts obs else observer_step_stmts obs)
    observers

let observer_locals observers = List.map observer_raw_vdecl observers
