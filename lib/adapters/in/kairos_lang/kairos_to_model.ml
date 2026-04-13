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

let node (n : Ast.node) : Verification_model.node_model =
  let sem = Ast.semantics_of_node n in
  let spec = Ast.specification_of_node n in
  {
    Verification_model.node_name = sem.sem_nname;
    inputs = sem.sem_inputs;
    outputs = sem.sem_outputs;
    locals = sem.sem_locals;
    states = sem.sem_states;
    init_state = sem.sem_init_state;
    steps =
      sem.sem_trans
      |> List.map Verification_model.step_of_ast_transition;
    assumes = spec.spec_assumes;
    guarantees = spec.spec_guarantees;
    state_invariants =
      List.map
        (fun (inv : Ast.invariant_state_rel) ->
          ({ state = inv.state; formula = inv.formula } : Verification_model.state_invariant))
        spec.spec_invariants_state_rel;
  }
  |> Verification_model.prioritize_node_steps

let program (p : Ast.program) : Verification_model.program_model =
  List.map node p

