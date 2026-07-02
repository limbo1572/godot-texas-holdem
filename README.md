# LocalPoker

Texas Hold'em — Godot 4.x. LAN multiplayer (ENet, host-authoritative), 2-6 players, side pots, auto-runout, tournament blind schedule, table UI. Offline mode vs bots included.

Blinds follow a hardcoded 10-level tournament schedule (10/20 -> 600/1200, 5 min per level). The level clock starts with the first hand of the session and level changes apply between hands; the host computes the timer, clients only display it.

## Play

Open the project in Godot and press F5 (main scene = lobby), or:

```bash
godot --path .
```

- **Host Game** — pick a port (default 8910), press Host, wait for players, press Start Game (needs 2+).
- **Join Game** — enter `host_ip:8910`, press Join. On the same machine use `127.0.0.1:8910`.
- **Play Offline vs Bots** — single-player table with 3 random bots.

## Manual 2-player LAN test (one machine)

1. Start two instances of the game (two terminals):
   `godot --path .` twice.
2. Window A: leave port 8910, press **Host Game**.
3. Window B: address `127.0.0.1:8910`, press **Join Game** — both lobbies list 2 players.
4. Window A: press **Start Game**. Both windows switch to the table; each sees only its own hole cards.
5. Play a full hand from both windows. Only the host sees **Next Hand** after showdown.
6. Watch the `[net]` console logs on both sides: every action request and state snapshot is printed.

## Architecture

- Host (peer 1) owns the single `GameState`; clients never instantiate it.
- Clients send `request_action` RPCs; the host validates against `get_legal_actions` and turn order.
- After every state change, the host sends a **personalized** snapshot per peer (`sync_state` via `rpc_id`) — opponents' hole cards are masked as `??` until showdown.
- Disconnect during a hand → the player is auto-folded and seated out for later hands.

## Headless debug hand (4 random bots, no network)

```bash
godot --headless --path . --script res://scripts/main.gd
```

## Tests

```bash
godot --headless --path . --script res://tests/test_hand_evaluator.gd
godot --headless --path . --script res://tests/test_network_manager.gd
godot --headless --path . --script res://tests/test_side_pots.gd
godot --headless --path . --script res://tests/test_blind_schedule.gd
```

Network end-to-end (two real processes over localhost — run host first, then client in a second terminal):

```bash
godot --headless --path . res://tests/e2e_host.tscn
godot --headless --path . res://tests/e2e_client.tscn
```

## Structure

- `scripts/card.gd`, `scripts/deck.gd` — cards and deck
- `scripts/hand_evaluator.gd` — best-five evaluation, kickers, hand comparison
- `scripts/pot_manager.gd` — main/side pots, uncalled-bet refunds, per-pot distribution
- `scripts/game_state.gd` — betting state machine (2-6 players, button rotation, runout, force_fold)
- `scripts/network_manager.gd` — autoload `Net`: ENet host/join, lobby player registry
- `scripts/network_game_controller.gd` — autoload `NetGame`: host-authoritative controller, RPCs, snapshots
- `scripts/lobby_ui.gd` + `scenes/lobby.tscn` — lobby (host/join/offline)
- `scripts/table_ui.gd` + `scenes/table.tscn` — table UI rendered from snapshots
- `scripts/main.gd` — headless demo hand
