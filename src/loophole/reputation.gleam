import gleam/int
import gleam/list
import loophole/engine

pub type Policy {
  RatingOnly
  BondBacked
}

pub type Rules {
  Rules(policy: Policy, threshold: Int, ceiling: Int)
}

pub type Strategy {
  Strategy(history: Int, small: Int, request: Int)
}

pub type Outcome {
  Start
  Delivered
  Defaulted
  RatingRejected
  CeilingRejected
  BondRejected
}

pub type Frame {
  Frame(
    step: Int,
    successes: Int,
    failures: Int,
    delivered: Int,
    bond: Int,
    seized: Int,
    loss: Int,
    amount: Int,
    outcome: Outcome,
  )
}

pub type Search {
  Search(
    strategy: Strategy,
    frames: List(Frame),
    baseline: List(Frame),
    tested: Int,
  )
}

pub fn default_rules() -> Rules {
  Rules(RatingOnly, 80, 64)
}

pub fn default_strategy() -> Strategy {
  Strategy(4, 1, 64)
}

pub fn initial() -> Frame {
  Frame(0, 0, 0, 0, 0, 0, 0, 0, Start)
}

/// A smoothed count-based rating: one positive and one negative prior.
pub fn rating(frame: Frame) -> Int {
  { frame.successes + 1 } * 100 / { frame.successes + frame.failures + 2 }
}

fn deliver(frame: Frame, amount: Int) -> Frame {
  Frame(
    ..frame,
    step: frame.step + 1,
    successes: frame.successes + 1,
    delivered: frame.delivered + amount,
    bond: frame.bond + amount,
    amount: amount,
    outcome: Delivered,
  )
}

/// Small prepaid deliveries build history and lock one credit per delivered unit.
/// The final request is the only transaction where a default can cause a loss.
pub fn run(rules: Rules, strategy: Strategy, betray: Bool) -> List(Frame) {
  let #(before, reversed) =
    engine.range(1, strategy.history)
    |> list.fold(#(initial(), [initial()]), fn(acc, _) {
      let frame = deliver(acc.0, strategy.small)
      #(frame, [frame, ..acc.1])
    })
  let score = rating(before)
  let rejected = case True {
    _ if score < rules.threshold -> RatingRejected
    _ if strategy.request > rules.ceiling -> CeilingRejected
    _ if rules.policy == BondBacked && strategy.request > before.bond ->
      BondRejected
    _ -> Start
  }
  let final = case rejected {
    Start ->
      case betray {
        False -> deliver(before, strategy.request)
        True -> {
          let seized = int.min(before.bond, strategy.request)
          Frame(
            ..before,
            step: before.step + 1,
            failures: 1,
            bond: before.bond - seized,
            seized: seized,
            loss: strategy.request - seized,
            amount: strategy.request,
            outcome: Defaulted,
          )
        }
      }
    _ ->
      Frame(
        ..before,
        step: before.step + 1,
        amount: strategy.request,
        outcome: rejected,
      )
  }
  list.reverse([final, ..reversed])
}

pub fn last(frames: List(Frame)) -> Frame {
  case list.last(frames) {
    Ok(frame) -> frame
    Error(_) -> initial()
  }
}

pub fn frame_at(frames: List(Frame), step: Int) -> Frame {
  case list.drop(frames, step) |> list.first {
    Ok(frame) -> frame
    Error(_) -> initial()
  }
}

pub fn strategies() -> List(Strategy) {
  list.flat_map([1, 2, 4, 8], fn(history) {
    list.flat_map([1, 2, 4], fn(small) {
      list.map([8, 16, 32, 64], fn(request) {
        Strategy(history, small, request)
      })
    })
  })
}

fn best(rules: Rules, seed: Strategy) -> Strategy {
  list.fold(strategies(), seed, fn(previous, candidate) {
    case
      last(run(rules, candidate, True)).loss
      > last(run(rules, previous, True)).loss
    {
      True -> candidate
      False -> previous
    }
  })
}

pub fn search(rules: Rules) -> Search {
  // Keep the rating-only counterexample when mitigation ties every candidate.
  // This makes the policy comparison inspectable without hiding a rejected ask.
  let seed = best(Rules(..rules, policy: RatingOnly), default_strategy())
  let strategy = best(rules, seed)
  Search(
    strategy,
    run(rules, strategy, True),
    run(rules, strategy, False),
    list.length(strategies()),
  )
}

pub fn policy_key(policy: Policy) -> String {
  case policy {
    RatingOnly -> "rating"
    BondBacked -> "bond"
  }
}

pub fn outcome_key(outcome: Outcome) -> String {
  case outcome {
    Start -> "start"
    Delivered -> "delivered"
    Defaulted -> "defaulted"
    RatingRejected -> "rating_rejected"
    CeilingRejected -> "ceiling_rejected"
    BondRejected -> "bond_rejected"
  }
}

pub fn outcome_label(outcome: Outcome) -> String {
  case outcome {
    Start -> "No history yet"
    Delivered -> "Delivery fulfilled"
    Defaulted -> "Request defaulted"
    RatingRejected -> "Rejected: rating too low"
    CeilingRejected -> "Rejected: request over limit"
    BondRejected -> "Rejected: insufficient collateral"
  }
}
