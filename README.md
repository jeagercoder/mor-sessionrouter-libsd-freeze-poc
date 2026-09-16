# MOR SessionRouter — permanent session-stake freeze via LibSD int64 overflow (PoC)

Unprivileged, permanent (unrecoverable) freeze of users' session stakes against the **deployed** Lumerin
diamond `0x6aBE1d282f72B474E54527D93b979A4f64d3030a` on Base.

**Root cause:** `LibSD.SD` uses `int64 mean/sqSum`; `add` computes `sqSum += (x-newMean)(x-oldMean)`. In
`SessionRouter._setStats` (L343) `x = int32(tpsScaled1000_)` comes from the **provider-signed receipt**
(attacker-controlled in a self-dealt session, full ±2.147e9 via `int32(uint32)`). `_setStats` is called
**unconditionally** by `closeSession` (L231). An attacker drives the shared per-(provider,model) accumulator
to the edge of int64 overflow, after which **any** user's `closeSession` on that provider+model overflows and
reverts forever → their staked MOR is frozen (no recovery: closeSession is the only refund path;
`withdrawUserStakes` only frees already-closed sessions; no admin reset). Setup: ~2 MOR, 11 txs.

## Run
```
docker run --rm --network host -v "$PWD":/w -w /w ghcr.io/foundry-rs/foundry:latest "forge test -vv"
```
Needs a Base RPC (tests hardcode base-rpc.publicnode.com).

## Tests
- `test/StatsBrick.t.sol` — END-TO-END on deployed diamond: attacker registers provider+model+bid, runs 11
  self-dealt sessions (real signed approvals/receipts) with crafted tps, then a victim opens+closes on the
  same provider+model and `closeSession` REVERTS (stake frozen).
- `test/LibSD.t.sol`, `test/LibSD2.t.sol` — isolated proofs the int64 accumulator can be wedged so any
  subsequent add overflows, with realistic incrementing counts.
- `test/Probe.t.sol` — reads the live diamond config.
