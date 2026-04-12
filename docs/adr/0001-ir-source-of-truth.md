# ADR-0001: IR as source of semantic truth

- Status: Accepted
- Date: 2026-04-12

## Context
Kairos produces several artifacts (DOT, text dumps, Why code, kobj). Historically, some debugging and proof discussions could drift toward generated artifacts as if they defined semantics.

## Decision
The canonical IR is the semantic source of truth for the reduction pipeline. Generated Why code and rendering outputs are compilation/render artifacts, not authoritative semantics.

## Consequences
- Semantics discussions must reference IR and exported kernel structures first.
- Backend fixes must preserve IR-driven meaning and avoid backend-only semantic patches.
- Debug traces should keep IR-to-obligation traceability explicit.

