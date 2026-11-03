# Reputation model, version 1

Implemented in `src/loophole/reputation.gleam`; introduced in Loophole v0.2.0.
All values are synthetic credits, not currency. This is an educational model of
trust exceeding collateral, not a fraud detector or a forecast of real behavior.

## One seller, two phases

The seller first fulfills a fixed number of small, prepaid deliveries. These
deliveries do not expose the buyer to an uncovered loss. Each delivered credit
is locked as seller collateral. For example, four one-credit deliveries create
four positive outcomes and lock four credits. This assumes enforceable escrow;
the credits are unavailable to the seller while locked.

The seller then makes one larger request. The system decides whether to approve
it using the rating and rules **before** that final transaction. If approved,
the baseline seller fulfills it and the strategic seller defaults. The trace
ends after this request, whether fulfilled, defaulted, or rejected.

## Rating and policies

The rating is a smoothed count of outcomes:

```text
rating = floor(100 × (successes + 1) / (successes + failures + 2))
```

The initial rating is 50. Four successes yield 83. One subsequent default drops
that rating to 71. A one-credit delivery counts just as much as a 64-credit
delivery. Rejected requests change neither successes nor failures.

Both approval policies enforce the minimum rating and global request ceiling.

- **Rating only:** those two checks are sufficient.
- **Rating + collateral:** the requested amount must also be no greater than
  the seller's already locked collateral.

Checks occur in that order: rating, ceiling, then collateral. The trace records
the first rejection reason. No collateral is seized on rejection.

When an approved request defaults:

```text
seized collateral = min(locked collateral, request)
uncovered loss = request − seized collateral
remaining collateral = previous collateral − seized collateral
```

When fulfilled, the final request adds a successful outcome and locks its value
as collateral, just like an earlier delivery. Every frame satisfies:

```text
remaining collateral + seized collateral = cumulative delivered credits
```

This is a deliberately simplified loss ledger. It does not estimate seller
profit, the cost of deliveries, or the opportunity cost of locked collateral.

## Finite search

Candidates are the Cartesian product of:

- Small deliveries: `[1, 2, 4, 8]`.
- Credits per small delivery: `[1, 2, 4]`.
- Final request: `[8, 16, 32, 64]`.

The 48 distinct candidates are ranked by final uncovered loss. The default rules
are rating threshold 80 and request ceiling 64. Search seeds the default strategy
`(4, 1, 64)` and replaces it only on strictly greater loss, with stable iteration
order. The baseline uses the selected history and request under identical rules,
but fulfills the final transaction if approved.

For a collateral-policy comparison, search first finds the rating-only attack
with the same threshold and ceiling, then re-evaluates all 48 candidates under
the selected policy. It retains that attack when loss ties. Thus the displayed
mitigation trace shows what happened to the original request instead of silently
substituting a different zero-loss candidate. The UI's strategy count denotes
distinct candidates, not the number of internal model invocations.

## Default result and tradeoffs

Four one-credit deliveries produce rating 83 and collateral 4. Rating-only
approval accepts a request for 64. Default seizes 4 and leaves **60 uncovered**.
The matched honest baseline has no default or uncovered loss.

At threshold 90, eight one-credit deliveries produce rating 90 and collateral 8.
The request for 64 still passes, leaving **56 uncovered** on default. At threshold
95, none of the enumerated histories qualifies. That means no attack was found
in this bounded set, not that reputation alone is safe.

With collateral approval, the default 64-credit request is rejected because only
4 credits are locked. The honest counterpart is rejected as well. Requests
covered by collateral can still default, but the collateral covers them in full.
For example, eight four-credit deliveries lock 32 credits; an accepted request
for 16 can default with 16 seized, 16 remaining, and zero uncovered loss.

The collateral rule prevents uncovered loss **under the modeled assumptions**.
It also constrains legitimate growth. Stable identities, accurate delivery
records, instant settlement, and fully enforceable collateral are material
assumptions. Fake reviews, Sybil identities, collusion, repeat defaults, escrow
failure, and enforcement costs are outside this experiment.

## Replay and export contracts

`#rep1:rating:80:64:searched:4` restores rating-only approval, minimum rating 80,
request ceiling 64, the searched strategy, and step 4. The `bond` policy key
selects collateral approval. `baseline` selects the initial honest strategy;
`searched` runs the finite adversarial search. Steps are clamped to the trace.

Exports use `loophole.reputation.v1` with model version `0.2.0`, rules, the chosen
strategy, honest-baseline loss, adversarial loss, and every frame. Each frame
includes step, successes, failures, delivered credits, collateral, seized
collateral, loss, transaction amount, rating, and outcome.

`node scripts/verify-replay.mjs receipt.json` reconstructs the selected search or
baseline using the compiled Gleam engine, compares every frame and summary, and
validates the replay fragment. It also continues accepting compute model v1
records from Loophole v0.1.0. Model versions are separate from the app release:
the unchanged compute model retains its original receipt version.
