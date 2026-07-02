# LocalPoker

Texas Hold'em — Godot 4.x. Stage 2: 2-6 players, side pots, auto-runout, basic table UI (local play vs random bots).

## Play (UI)

Open the project in Godot and press F5, or run:

```bash
godot --path .
```

You are the bottom seat; three random bots fill the rest. Fold / Check / Call / Raise (slider) / All-In buttons appear on your turn.

## Headless debug hand (4 random bots)

```bash
godot --headless --path . --script res://scripts/main.gd
```

## Tests

```bash
godot --headless --path . --script res://tests/test_hand_evaluator.gd
godot --headless --path . --script res://tests/test_side_pots.gd
```

## Structure

- `scripts/card.gd`, `scripts/deck.gd` — cards and deck
- `scripts/hand_evaluator.gd` — best-five evaluation, kickers, hand comparison
- `scripts/pot_manager.gd` — main/side pot construction, uncalled-bet refunds, per-pot distribution
- `scripts/game_state.gd` — betting state machine for 2-6 players, button rotation, auto-runout
- `scripts/main.gd` — headless demo hand with random bots
- `scripts/table_ui.gd` + `scenes/table.tscn` — table UI
