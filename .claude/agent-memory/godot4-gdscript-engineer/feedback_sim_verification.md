---
name: feedback-sim-verification
description: After any gameplay change, run all 6 sim strategies to confirm none are broken before committing
metadata:
  type: feedback
---

After every gameplay change — especially mechanic additions/removals — run the full simulation suite with all 6 strategies before committing.

**Why:** The user explicitly requested this after the shop removal: "run simulations for all strategies. if any strategy is broken because the removal of the shop screen, fix it." This is the acceptance criterion for gameplay PRs.

**How to apply:**
- Command: `godot --headless --path . --script res://scripts/sim/sim_runner.gd -- --runs 100 --strategies random,greedy,word_search,diagonal_cluster,corner_spiral,hybrid_word_diagonal --seed 42`
- Godot binary: `C:\Users\suporte\Documents\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64.exe`
- Also run the test harness: `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd` — all 29 cases must pass (TC1–TC14, TS1–TS6, TSM1–TSM6).
- Fix any broken strategy before pushing. Do not relax tests to make them pass.

[[feedback-no-paper-over-failures]]
