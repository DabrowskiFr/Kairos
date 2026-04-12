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

let mk_stmt ?loc stmt = { stmt; loc }
let stmt_desc s = s.stmt
let with_stmt_desc s stmt = { s with stmt }

let mk_transition ~src ~dst ~guard ~body : transition = { src; dst; guard; body }

let mk_node ~nname ~inputs ~outputs ~assumes ~guarantees ~instances ~locals ~states ~init_state
    ~trans : node =
  {
    semantics =
      {
        sem_nname = nname;
        sem_inputs = inputs;
        sem_outputs = outputs;
        sem_instances = instances;
        sem_locals = locals;
        sem_states = states;
        sem_init_state = init_state;
        sem_trans = trans;
      };
    specification =
      {
        spec_assumes = assumes;
        spec_guarantees = guarantees;
        spec_invariants_state_rel = [];
      };
  }
