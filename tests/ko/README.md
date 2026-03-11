# Generated `ko` suite

For each file in `tests/ok/inputs`, this directory contains three negative variants:

- `__bad_spec`: wrong global specification
- `__bad_invariant`: wrong user invariant
- `__bad_code`: wrong program code

`__bad_code` variants are intentionally still executable and well-formed:
they rewrite output-producing code on an active path into type-correct but
semantically wrong updates, preferring non-init transitions when available.
