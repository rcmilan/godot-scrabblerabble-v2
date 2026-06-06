---
name: feedback-probabilistic-test-relaxation
description: When an upgrade offer becomes probabilistic, relax the sim test to accept any valid outcome — don't hardcode one expected value
metadata:
  type: feedback
---

When game behaviour becomes probabilistic (e.g. upgrade offer randomised to 2x or 3x), update sim tests to accept any valid outcome instead of a single expected value.

```gdscript
# WRONG after randomisation — will fail 1/3 of the time
assert(core.letter_modifiers[letter] == GameCore.MOD_2X)

# CORRECT
var v: String = core.letter_modifiers[letter]
if v != GameCore.MOD_2X and v != GameCore.MOD_3X:
    push_error("TSM10: expected MOD_2X or MOD_3X, got '%s'" % v)
    return false
```

**Why:** TSM10 originally checked for exactly MOD_2X. After the upgrade offer was randomised (1/3 → 3x), the test failed on any seed that rolled 3x. The fix is to assert the value is *one of the valid options*, not a specific one.

**How to apply:** Any time you add randomness to a mechanic that a test case asserts on, audit the test immediately. Do not paper over the failure by seeding to a known value — that's fragile. Broaden the assertion to the full valid set instead. [[feedback-sim-verification]]
