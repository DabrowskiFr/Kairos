(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let run (ready : Lsp_run_preflight.ready)
    (callbacks : Lsp_run_notifications.t) ~should_cancel =
  let decoded = ready.decoded in
  let lsp_cfg = Lsp_run_config.lsp_config decoded in
  Lsp_backend_usecases.run_with_callbacks
    ~engine:decoded.engine
    ~should_cancel lsp_cfg
    ~on_outputs_ready:callbacks.on_outputs_ready
    ~on_goals_ready:callbacks.on_goals_ready
    ~on_goal_done:callbacks.on_goal_done
