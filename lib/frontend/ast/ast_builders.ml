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

let mk_iexpr ?loc iexpr = { iexpr; loc }
let iexpr_desc e = e.iexpr
let with_iexpr_desc e iexpr = { e with iexpr }
let mk_var v = mk_iexpr (IVar v)
let mk_int n = mk_iexpr (ILitInt n)
let mk_bool b = mk_iexpr (ILitBool b)
let as_var e = match e.iexpr with IVar v -> Some v | _ -> None
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
