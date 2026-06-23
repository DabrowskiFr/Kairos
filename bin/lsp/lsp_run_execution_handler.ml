(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let handle (ctx : Lsp_run_context.t) ~id ~params =
  let oc = ctx.out_channel in
  match Lsp_run_preflight.check ctx ~id ~params with
  | Canceled -> Lsp_run_response.send_canceled oc ~id
  | Invalid_input -> Lsp_run_response.send_invalid_input oc ~id
  | Ready ready -> (
        let progress = Lsp_run_progress.start ctx in
        Lsp_run_progress.report progress
          ~message:
            (if ready.decoded.cfg.prove then "Proving Kairos obligations ..."
             else "Building Kairos artifacts ...");
        let callbacks =
          Lsp_run_notifications.create ~out_channel:oc ~id ~progress
            ~prove:ready.decoded.cfg.prove
        in
        (match
           Lsp_run_backend.run ready callbacks
             ~should_cancel:(fun () -> Lsp_run_preflight.is_canceled ctx ready)
         with
        | Ok out ->
            if Lsp_run_preflight.is_canceled ctx ready then
              Lsp_run_response.send_canceled oc ~id
            else (
              Lsp_run_progress.finish progress ~message:"Done";
              Lsp_run_response.send_outputs oc ~id out)
        | Error msg -> Lsp_run_response.send_backend_error oc ~id msg))
