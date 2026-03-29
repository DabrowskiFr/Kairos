These examples are intentionally excluded from the current ok/ko campaigns.

Files:
- sticky_bypass_echo.kairos
- gated_echo_bundle.kairos

Reason:
- The intended property is "sample on rising edge, then hold".
- The natural specification therefore needs a trigger on the rising edge of
  the input, e.g. `gate = 1 and not prev gate = 1` or
  `bypass = 1 and not prev bypass = 1`.
- In the current frontend/monitor pipeline, atoms such as `prev(gate)` and
  `prev(bypass)` on inputs are not translatable to monitor expressions.
- If we weaken the spec to trigger on the level (`gate = 1` / `bypass = 1`)
  instead of the edge, the property becomes too strong for these programs:
  once the program is already in the hold state, a later high input level
  would retrigger the spec, but the code does not resample.

Current status:
- These examples are not good ok tests under the current monitorizable
  specification fragment.
- They should stay out of automated campaigns until the language/export path
  can express the intended rising-edge trigger.
