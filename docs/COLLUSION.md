# The review ring

An executable toy model of review inflation and a partial mitigation. The review
model version is `0.3.0`; its export schema is `loophole.collusion.v1`. Earlier
compute and reputation schemas retain their own versions.

## Fixed feedback and costs

Four distinct genuine reviewers each give two stars: 40 on a 0–100 scale.
Coordinated accounts submit only five-star reviews (100). Opening an account
costs 2 synthetic budget units; each posted review costs 1. These are illustrative
costs, not estimates of any real platform. Genuine feedback never changes.

The weighted score is the integer floor of `(160 + 100 * counted) / (4 + counted)`.
Under **Every review counts**, every coordinated post adds one vote. Under
**One vote per reviewer**, only the first post from each coordinated account adds
weight. Ignored posts still consume budget. A seller is promoted only at the final
decision if the score is at least the configured threshold.

## Bounded search and trace

The 24 candidates are the Cartesian product of:

- Accounts: 1, 2, 3, 4, 6, 8.
- Reviews per account: 1, 2, 4, 8.

Cost is `accounts * (2 + reviews_per_account)`. Search discards candidates exceeding
the budget, maximizes the final integer score, then prefers lower cost. Remaining
ties keep the first candidate in the listed order. UI budgets are 3–40, ensuring
at least one affordable candidate. Thresholds are 50–99.

A trace starts with genuine feedback, opens every coordinated account, posts
reviews round-robin, then evaluates promotion. Attempting an unaffordable strategy
produces a rejection frame without spending. The honest baseline has only the
initial frame and a decision, with rating 40 and no coordinated accounts.
At every step, `spent = 2 * opened_accounts + posted_reviews`.

## Three reproducible results

| Rule | Budget | Best strategy | Cost | Rating | Promotion at 80 |
| --- | ---: | --- | ---: | ---: | --- |
| Every review | 20 | 2 accounts × 8 reviews | 20 | 88 | Yes |
| One vote per reviewer | 20 | 6 accounts × 1 review | 18 | 76 | No |
| One vote per reviewer | 24 | 8 accounts × 1 review | 24 | 80 | Yes |

The cap removes the benefit of repetition. Search adapts by buying more accounts.
It still raises the rating by 36 points at budget 20, even when promotion is blocked.
The limit-test button explicitly sets one vote per reviewer, budget 24, threshold 80.

## Replay and verification

Links use `#ring1:<all|unique>:<budget>:<threshold>:<baseline|searched>:<step>`.
The UI clamps supported numeric parameters and replay positions. JSON includes
rules, strategy, search counts, final result, replay position, and every frame.
The independent Node command recomputes these through the compiled Gleam engine;
it does not trust exported rating or accounting fields.

```sh
npm run build
node scripts/verify-replay.mjs /path/to/loophole-collusion-v1.json
```

Six Gleam tests cover the default exploit, adaptive mitigation, bypass, rejection,
accounting over 240 strategy/policy/budget traces, and optimal deterministic search.
Node tests validate 60 UI-generated records and reject altered records.

## Limits

This is a bounded demonstration, not a discovery of review manipulation or a
security proof. It has no network activity, real accounts, real transactions, or
inference service. The simulator knows which reviews are coordinated because it
created them; the policy has no collusion-detection capability. Stable reviewer
identifiers do not establish independent people. Genuine opinions, account costs,
review costs, and visibility are fixed. Purchase verification, identity checks,
trust networks, account age, negative attacks, retaliation, detection, and adaptive
multi-round strategies are outside this model. A higher rating is not profit.
