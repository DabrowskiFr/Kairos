(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let send_begin (oc : out_channel) ~(token : string) ~(title : string)
    ~(message : string) : unit =
  Lsp_transport_messages.send_notification oc ~method_name:"$/progress"
    ~params_json:
      (`Assoc
        [
          ("token", `String token);
          ( "value",
            `Assoc
              [
                ("kind", `String "begin");
                ("title", `String title);
                ("message", `String message);
              ] );
        ])

let send_report (oc : out_channel) ~(token : string) ~(message : string) :
    unit =
  Lsp_transport_messages.send_notification oc ~method_name:"$/progress"
    ~params_json:
      (`Assoc
        [
          ("token", `String token);
          ( "value",
            `Assoc [ ("kind", `String "report"); ("message", `String message) ]
          );
        ])

let send_end (oc : out_channel) ~(token : string) ~(message : string) : unit =
  Lsp_transport_messages.send_notification oc ~method_name:"$/progress"
    ~params_json:
      (`Assoc
        [
          ("token", `String token);
          ( "value",
            `Assoc [ ("kind", `String "end"); ("message", `String message) ] );
        ])
