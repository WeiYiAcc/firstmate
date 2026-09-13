Mode: dirge (bounded foreground wait).

This primary harness has NO verified watcher wake adapter. dirge publishes no
harness-identity marker of its own, is detected by ancestry alone (a single
`dirge` process in the chain), and ships no session-open or turn-end hook that
firstmate tracks. So supervision here uses a bounded foreground wait rather
than an armed background cycle.

When this session owns supervision and away mode is not active:
1. Drain first with `bin/fm-wake-drain.sh`.
   After handling all emitted wakes and reconciling open decisions and unread status lines, run the exact `--ack-through` command printed as `WAKE_ACK_REQUIRED`; until then the work remains durable for idempotent re-handling after interruption.
2. Choose a supervision wait the harness can actually wake from: a BOUNDED foreground wait over `bin/fm-watch.sh` run through the bash tool, so the tool call returns on its own deadline and the next turn re-drains.
   dirge has no tracked background mechanism that survives the tool call and notifies the model on process exit, so `bin/fm-watch-arm.sh` is NOT usable here - it would either wedge the agent or orphan its child.
3. Never use shell `&` for watcher supervision, and never background, pipe, or bundle the wait to fake an armed cycle.
4. Repeat: after each bounded wait returns, drain, handle every emitted wake, reconcile open decisions and unread status lines, acknowledge with the printed `--ack-through` command, then start the next bounded wait while supervision is still required.
5. Failure or missing cycle only: inspect the failure text and restore the same bounded foreground wait shape; do not substitute a different harness's wait mechanism.

A turn that is described as holding or waiting still must not end blind while work is under way: the bounded wait is what carries supervision across turns here, so re-arm it (or leave it running) before the turn ends.

The Pi supervision branch (`docs/pi-supervision-branch.md`) and the Claude Stop-hook cycle (`docs/supervision-protocols/claude.md`) are both out of scope for the dirge primary: every actionable wake is delivered to this conversation, and the lease, outcome-store, and hook-owned contracts do not apply here.

Promotion rule: this snippet is named (not the `unknown` fallback) because the ancestry evidence is verified - `ps -o comm=` reports the bare word `dirge` and `bin/fm-harness.sh` resolves it. Record further verification evidence here before adding any armed-background or hook-owned wake path.
