type topology_route = {
  route : Kx_core_syntax.ident;
  tracks : Kx_core_syntax.ident list;
  points : (Kx_core_syntax.ident * Kx_core_syntax.ident) list;
}
[@@deriving yojson]

type topology_entry =
  | TRoute of topology_route
  | TConflict of Kx_core_syntax.ident * Kx_core_syntax.ident
  | TRouteSignal of Kx_core_syntax.ident * Kx_core_syntax.ident
[@@deriving yojson]
