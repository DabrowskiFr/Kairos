# Negative regression cases

Each file describes one understandable programming or specification mistake.
When an `OK` counterpart exists, the negative file changes exactly one
semantic element: the implementation, an invariant, or a contract.

[`expectations.tsv`](expectations.tsv) records the boundary at which every
case must be rejected:

- `frontend`: parsing, elaboration, typing, ownership, or initialization;
- `pipeline`: a scientific pipeline constraint checked after elaboration;
- `proof`: a well-formed program whose generated obligations are not all
  proved.

The fast corpus check is part of `dune runtest`. The complete solver campaign
is available through:

```sh
dune build @proof-regression
```

An outer harness timeout, an internal error, an unexpected solver status, or a
negative case that becomes green fails the campaign.
