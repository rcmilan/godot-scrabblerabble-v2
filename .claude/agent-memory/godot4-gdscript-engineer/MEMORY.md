# Memory Index

- [Icons Not Text for Upgrades](feedback_icons_not_text.md) — Upgrade items must show graphical mod2x tile icon drawn via _draw, not plain text labels
- [Keyboard Nav Pattern](feedback_keyboard_nav_pattern.md) — Focusable controls use FOCUS_ALL + _gui_input; mirrors board_cell.gd and END TURN button
- [Sim Verification Required](feedback_sim_verification.md) — All 6 strategies must pass after any gameplay change before committing; 29 tests must pass
- [Panel vs Container for Positioning](project_panel_vs_container_positioning.md) — Free anchor layout_mode=0 only works under Panel parents (WinFrame), not VBoxContainer (GameArea)
- [Upgrade Column Architecture](project_upgrade_column_architecture.md) — Shop removed; UpgradeColumn replaces it as left-side panel, accumulates unpicked upgrades
- [New Modifier Checklist](project_new_modifier_checklist.md) — 7-file checklist for adding any new tile modifier (constants, visuals, scoring x3, sim parity, tests)
- [Untyped Array Type Inference](feedback_untyped_array_inference.md) — Use `var x: String = arr[i]` not `:=` when reading from plain Array; GDScript can't infer type
- [Upgrade Dialog Flow](project_upgrade_dialog_flow.md) — Two-step upgrade dialog: roll offer (2/3 2x, 1/3 3x) → modifier pick → letter pick → RunState.set_letter_modifier
- [Probabilistic Test Relaxation](feedback_probabilistic_test_relaxation.md) — When behaviour is randomised, broaden sim assertions to accept any valid outcome, not one specific value
