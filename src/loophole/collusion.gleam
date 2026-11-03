import gleam/list
import loophole/engine

pub type Policy {
  EveryReview
  OnePerReviewer
}

pub type Rules {
  Rules(policy: Policy, budget: Int, threshold: Int)
}

pub type Strategy {
  Strategy(accounts: Int, repeats: Int)
}

pub type Event {
  Start
  AccountOpened
  ReviewPosted
  Decision
  BudgetRejected
}

pub type Frame {
  Frame(step: Int, reviews: List(Int), spent: Int, event: Event, reviewer: Int)
}

pub type Search {
  Search(
    strategy: Strategy,
    frames: List(Frame),
    baseline: List(Frame),
    tested: Int,
    feasible: Int,
  )
}

pub fn default_rules() -> Rules {
  Rules(EveryReview, 20, 80)
}

pub fn default_strategy() -> Strategy {
  Strategy(2, 8)
}

pub fn initial() -> Frame {
  Frame(0, [], 0, Start, -1)
}

pub fn cost(strategy: Strategy) -> Int {
  strategy.accounts * { 2 + strategy.repeats }
}

pub fn posted(frame: Frame) -> Int {
  list.fold(frame.reviews, 0, fn(sum, count) { sum + count })
}

pub fn counted(frame: Frame, policy: Policy) -> Int {
  case policy {
    EveryReview -> posted(frame)
    OnePerReviewer ->
      list.filter(frame.reviews, fn(count) { count > 0 }) |> list.length
  }
}

/// Four distinct genuine reviewers each give two stars (40/100).
/// Every coordinated review gives five stars (100/100).
pub fn rating(frame: Frame, policy: Policy) -> Int {
  let votes = counted(frame, policy)
  { 160 + votes * 100 } / { 4 + votes }
}

pub fn promoted(frame: Frame, rules: Rules) -> Bool {
  frame.event == Decision && rating(frame, rules.policy) >= rules.threshold
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

pub fn run(rules: Rules, strategy: Strategy, attack: Bool) -> List(Frame) {
  case attack {
    False -> [initial(), Frame(..initial(), step: 1, event: Decision)]
    True ->
      case cost(strategy) > rules.budget {
        True -> [initial(), Frame(..initial(), step: 1, event: BudgetRejected)]
        False -> {
          let #(opened, history) =
            engine.range(1, strategy.accounts)
            |> list.fold(#(initial(), [initial()]), fn(acc, _) {
              let frame =
                Frame(
                  acc.0.step + 1,
                  list.append(acc.0.reviews, [0]),
                  acc.0.spent + 2,
                  AccountOpened,
                  list.length(acc.0.reviews),
                )
              #(frame, [frame, ..acc.1])
            })
          let #(reviewed, history) =
            engine.range(0, strategy.accounts * strategy.repeats - 1)
            |> list.fold(#(opened, history), fn(acc, index) {
              let reviewer = index % strategy.accounts
              let reviews =
                list.index_map(acc.0.reviews, fn(count, id) {
                  case id == reviewer {
                    True -> count + 1
                    False -> count
                  }
                })
              let frame =
                Frame(
                  acc.0.step + 1,
                  reviews,
                  acc.0.spent + 1,
                  ReviewPosted,
                  reviewer,
                )
              #(frame, [frame, ..acc.1])
            })
          let final =
            Frame(
              ..reviewed,
              step: reviewed.step + 1,
              event: Decision,
              reviewer: -1,
            )
          list.reverse([final, ..history])
        }
      }
  }
}

pub fn strategies() -> List(Strategy) {
  list.flat_map([1, 2, 3, 4, 6, 8], fn(accounts) {
    list.map([1, 2, 4, 8], fn(repeats) { Strategy(accounts, repeats) })
  })
}

pub fn search(rules: Rules) -> Search {
  let feasible =
    list.filter(strategies(), fn(strategy) { cost(strategy) <= rules.budget })
  let strategy =
    list.fold(feasible, Strategy(1, 1), fn(best, candidate) {
      let previous_score = rating(last(run(rules, best, True)), rules.policy)
      let score = rating(last(run(rules, candidate, True)), rules.policy)
      case
        score > previous_score
        || { score == previous_score && cost(candidate) < cost(best) }
      {
        True -> candidate
        False -> best
      }
    })
  Search(
    strategy,
    run(rules, strategy, True),
    run(rules, strategy, False),
    list.length(strategies()),
    list.length(feasible),
  )
}

pub fn policy_key(policy: Policy) -> String {
  case policy {
    EveryReview -> "all"
    OnePerReviewer -> "unique"
  }
}

pub fn event_key(event: Event) -> String {
  case event {
    Start -> "start"
    AccountOpened -> "account_opened"
    ReviewPosted -> "review_posted"
    Decision -> "decision"
    BudgetRejected -> "budget_rejected"
  }
}
