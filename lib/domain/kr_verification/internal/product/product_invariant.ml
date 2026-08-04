(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type t = {
  family : string;
  entry_facts :
    Kr_verification_ir.product_state ->
    Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list;
  preservation_facts :
    node:Kr_domain_core_syntax.historical Kr_verification_ir.node_ir ->
    Kr_domain_core_syntax.historical Kr_verification_ir.product_step_summary ->
    Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list;
}

let of_reachability analysis =
  {
    family = "product_reachability";
    entry_facts =
      Kr_verification_reachability.entry_facts_of_product_state analysis;
    preservation_facts =
      (fun ~node:_ ->
        Kr_verification_reachability.preservation_ensures analysis);
  }

let of_characteristics analysis =
  {
    family = "product_characteristics";
    entry_facts =
      Kr_verification_characteristics.entry_facts_of_product_state analysis;
    preservation_facts =
      (fun ~node ->
        Kr_verification_characteristics.preservation_ensures analysis ~node);
  }

let entry_facts invariants state =
  List.map
    (fun invariant ->
      (invariant.family, invariant.entry_facts state))
    invariants

let preservation_facts invariants ~node summary =
  List.map
    (fun invariant ->
      (invariant.family,
       invariant.preservation_facts ~node summary))
    invariants
