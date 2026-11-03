# Shared compute model, version 1

This document specifies the behavior implemented in `src/loophole/engine.gleam`.

## State and workload

There are four stable user identities: Atlas (0), Nova (1), Moss (2), and Rogue
(3). Each has 12 units of work. A job records its unique ID, owner, and remaining
units. A frame records the elapsed tick count, last served user, cumulative
allocated and submitted units per user, and the ordered pending queue.

`completed` is the engine's field name for allocated compute units. It does not
count completed jobs. The JSON export uses the clearer name `allocated`.

## Tick order

1. Admit jobs for users 0 through 3, in that order. Users cannot exceed either
   their 12-unit workload or the per-user cap on pending jobs.
2. Atlas, Nova, and Moss each submit up to one four-unit job per tick.
3. Rogue submits according to its chunk size, burst limit, and start delay.
   A partial final chunk is allowed. Delay 4 means the first possible admission
   occurs in the transition from frame 4 to frame 5.
4. Choose a pending job according to the policy.
5. Allocate one compute unit to its owner, subtract one from the job, and remove
   the job if it reaches zero. There is no nonpreemptive lock or switch cost.
6. Record the new frame. If no job is pending, record an idle tick.

The first frame is tick 0 with no submissions or allocated work. Exactly one
unit is served per non-idle tick. Job IDs encode the admission tick, owner, and
slot within the burst. The UI caps bursts at 4 and pending queues at 8.

## Policies

**Shortest job first** is shortest *remaining* work at each tick. Ties prioritize
users cyclically, starting after the previous served user. Remaining ties use
the earliest job ID.

**Fair rotation** prioritizes users cyclically after the previous served user,
then earliest job ID. It skips users without pending work and ignores job size.

## Strategy search and baseline

Candidates are the Cartesian product of:

- Chunk size: `[1, 2, 3, 4]` compute units.
- Maximum submission burst: `[1, 2, 4]` jobs per tick.
- Start delay: `[0, 2, 4]` ticks.

All 36 candidates run against the same rules and three normal users. The
objective is Rogue's allocated compute at the observation horizon. The baseline
is chunk 4, burst 1, delay 0 under those exact same rules. Search starts with the
baseline and replaces it only on strictly greater allocation; ties are stable.

The default configuration (shortest first, cap 4, horizon 24) produces baseline
allocation `[8, 8, 4, 4]` and best-found allocation `[4, 4, 4, 12]`. The selected
strategy is chunk 1, burst 1, delay 0: extra flooding is unnecessary. Fair
rotation at the same cap and horizon produces `[6, 6, 6, 6]` and zero gain.

## Replays

A fragment such as `#v1:shortest:4:24:searched:12` encodes the model version,
policy, cap, horizon, whether to search, and displayed tick. Opening the replay
link in a new tab reconstructs the experiment locally. It contains no personal
information. The app does not upload or persist experiments.

JSON exports use `loophole.replay.v1` and include rules, strategy, summary counts,
the replay fragment, and all frames. `scripts/verify-replay.mjs` independently
re-runs the exported configuration through the compiled engine and compares the
record. It is an integrity check, not cryptographic authentication.

## Interpretation

Finite search can find a counterexample; failing to find one proves nothing
outside the enumerated set. The 48-tick horizon gives every user enough time to
finish all work, concealing earlier unfairness in the final totals. Replay the
prefix to observe it. Fair rotation's stable-identity assumption is material.
This is an educational simulation, not a production scheduler benchmark.
