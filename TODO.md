./scripts/validate_ok_ko.sh . 5 legacy
./scripts/validate_ok_ko.sh . 5 without_calls
./scripts/validate_ok_ko.sh . 5 with_calls
./scripts/validate_ok_ko.sh . 5 split

./scripts/validate_ok_ko.sh . 5 single_ok 60 tests/ok/armed_delay.kairos
./scripts/validate_ok_ko.sh . 5 single_ko 60 tests/ko/foo__bad_spec.kairos
Le choix entre les deux dépend du statut attendu :

single_ok : le fichier est censé passer
single_ko : le fichier est censé échouer



opam exec -- _build/default/bin/cli/main.exe tests/ok/delay_int2.kairos \
  --dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 20 --timeout-s 5
