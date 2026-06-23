(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type 'ctx t =
  | Any of {
      method_name : string;
      handle : 'ctx -> unit;
    }
  | Notification of {
      method_name : string;
      handle : 'ctx -> unit;
    }
  | Request of {
      method_name : string;
      handle : 'ctx -> id:Jsonrpc.Id.t -> unit;
    }

let any method_name handle = Any { method_name; handle }
let notification method_name handle = Notification { method_name; handle }
let request method_name handle = Request { method_name; handle }

let method_name = function
  | Any { method_name; _ } -> method_name
  | Notification { method_name; _ } -> method_name
  | Request { method_name; _ } -> method_name

let find routes target_method =
  List.find_opt
    (fun route -> String.equal (method_name route) target_method)
    routes

let dispatch route ctx ~id_json =
  match route with
  | Any { handle; _ } -> handle ctx
  | Notification { handle; _ } -> handle ctx
  | Request { handle; _ } -> Option.iter (fun id -> handle ctx ~id) id_json
