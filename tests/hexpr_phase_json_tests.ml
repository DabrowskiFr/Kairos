open Core_syntax
open Core_syntax_builders

let fail message =
  prerr_endline message;
  exit 1

let () =
  let historical : historical hexpr = mk_hpre_k "x" 2 in
  let historical_json = hexpr_to_yojson historical in
  let expected_historical_json =
    `Assoc
      [
        ( "hexpr",
          `List
            [
              `String "HPreK";
              `List [ `String "x"; `Int 2 ];
            ] );
        ("loc", `Null);
      ]
  in
  if historical_json <> expected_historical_json then
    fail "historical encoder changed the established JSON representation";
  (match historical_hexpr_of_yojson historical_json with
  | Ok decoded when decoded = historical -> ()
  | Ok _ -> fail "historical decoder changed the formula"
  | Error message ->
      fail ("historical decoder rejected HPreK: " ^ message));
  (match history_free_hexpr_of_yojson historical_json with
  | Error _ -> ()
  | Ok _ -> fail "history-free decoder accepted HPreK");

  let history_free : history_free hexpr =
    mk_hexpr (HCmp (REq, mk_hvar "x", mk_hint 1))
  in
  let history_free_json = hexpr_to_yojson history_free in
  (match history_free_hexpr_of_yojson history_free_json with
  | Ok decoded when decoded = history_free -> ()
  | Ok _ -> fail "history-free decoder changed the formula"
  | Error message ->
      fail ("history-free decoder rejected a valid formula: " ^ message));
  (match historical_hexpr_of_yojson history_free_json with
  | Ok _ -> ()
  | Error message ->
      fail ("historical decoder rejected a history-free formula: " ^ message));
  print_endline "hexpr_phase_json_tests: ok"
