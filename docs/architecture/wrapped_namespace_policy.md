# Wrapped Namespace Policy

Date: 2026-07-02

Kairos should use Dune's default wrapped libraries for new code.  `(wrapped
false)` remains a compatibility mechanism for existing libraries, not the
default architecture.

## Rule

New libraries must be wrapped unless there is a documented reason not to do so.
The expected shape is:

- one small public facade for the subsystem;
- implementation modules kept private when possible;
- external callers depend on the facade, not on implementation modules;
- module names remain meaningful inside the subsystem, where local aliases are
  acceptable.

`(wrapped false)` may be kept only when at least one of these conditions holds:

- migrating it would cause broad source churn unrelated to the current change;
- the library intentionally provides a flat compatibility surface;
- the library is waiting for a facade/API split.

Each exception should name the reason and a plausible removal condition before
it is migrated.

## Migration Procedure

1. Identify the public facade actually used by downstream code.
2. Qualify downstream uses through the wrapped library namespace.
3. Mark implementation modules as private if downstream code should not depend
   on them.
4. Remove `(wrapped false)`.
5. Ratchet `DEFAULT_MAX_WRAPPED_FALSE` in
   `scripts/check_quality_baseline.py`.
6. Run `dune build @all`, `dune build @fmt`, `dune runtest`, and subsystem
   validation.

This is intentionally incremental.  A single migration should improve
namespace discipline without mixing unrelated semantic changes.

## Pilot

The pilot subsystem is `kairos_c_codegen`.

Reasons:

- it is small and recently split by responsibility;
- it already has a public `C_codegen` facade;
- downstream use is limited to the CLI C-emission path;
- its implementation modules are backend internals and should not be consumed
  directly.

Pilot result:

- `kairos_c_codegen` is wrapped;
- `c_codegen_types`, `c_codegen_common`, `c_codegen_names`,
  `c_codegen_env`, `c_codegen_expr`, `c_codegen_stmt`,
  `c_codegen_functions`, `c_codegen_node`, and `c_codegen_program` are private;
- CLI callers use `Kairos_c_codegen.C_codegen`;
- the quality baseline allows at most 28 `(wrapped false)` declarations.
