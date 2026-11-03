import gleam/list
import gleeunit/should
import loophole/collusion as ring

pub fn repeated_reviews_manufacture_promotion_test() {
  let found = ring.search(ring.default_rules())
  found.tested |> should.equal(24)
  found.feasible |> should.equal(14)
  found.strategy |> should.equal(ring.Strategy(2, 8))
  let final = ring.last(found.frames)
  ring.rating(final, ring.EveryReview) |> should.equal(88)
  final.spent |> should.equal(20)
  ring.promoted(final, ring.default_rules()) |> should.be_true
  ring.rating(ring.last(found.baseline), ring.EveryReview) |> should.equal(40)
}

pub fn cap_changes_optimal_strategy_but_leaves_inflation_test() {
  let rules = ring.Rules(ring.OnePerReviewer, 20, 80)
  let found = ring.search(rules)
  found.strategy |> should.equal(ring.Strategy(6, 1))
  ring.rating(ring.last(found.frames), rules.policy) |> should.equal(76)
  ring.promoted(ring.last(found.frames), rules) |> should.be_false
  // Keeping the original repeat-heavy strategy only reaches 60.
  let original = ring.run(rules, ring.Strategy(2, 8), True) |> ring.last
  ring.rating(original, rules.policy) |> should.equal(60)
  ring.posted(original) |> should.equal(16)
  ring.counted(original, rules.policy) |> should.equal(2)
}

pub fn more_accounts_bypass_cap_test() {
  let rules = ring.Rules(ring.OnePerReviewer, 24, 80)
  let found = ring.search(rules)
  found.strategy |> should.equal(ring.Strategy(8, 1))
  ring.rating(ring.last(found.frames), rules.policy) |> should.equal(80)
  ring.promoted(ring.last(found.frames), rules) |> should.be_true
}

pub fn over_budget_plan_spends_nothing_test() {
  let final =
    ring.run(ring.default_rules(), ring.Strategy(8, 8), True) |> ring.last
  final.event |> should.equal(ring.BudgetRejected)
  final.spent |> should.equal(0)
  final.reviews |> should.equal([])
  ring.promoted(final, ring.default_rules()) |> should.be_false
}

pub fn budget_and_vote_accounting_for_every_candidate_test() {
  list.each([ring.EveryReview, ring.OnePerReviewer], fn(policy) {
    list.each([3, 10, 20, 24, 40], fn(budget) {
      let rules = ring.Rules(policy, budget, 80)
      list.each(ring.strategies(), fn(strategy) {
        let frames = ring.run(rules, strategy, True)
        list.each(frames, fn(frame) {
          should.equal(
            frame.spent,
            list.length(frame.reviews) * 2 + ring.posted(frame),
          )
          should.be_true(frame.spent <= budget)
          should.be_true(ring.counted(frame, policy) <= ring.posted(frame))
          should.be_true(
            ring.rating(frame, policy) >= 40
            && ring.rating(frame, policy) <= 100,
          )
          case policy {
            ring.OnePerReviewer ->
              should.be_true(
                ring.counted(frame, policy) <= list.length(frame.reviews),
              )
            _ -> Nil
          }
          case frame.event {
            ring.Decision -> Nil
            _ -> ring.promoted(frame, rules) |> should.be_false
          }
        })
        let final = ring.last(frames)
        case ring.cost(strategy) <= budget {
          True -> {
            final.spent |> should.equal(ring.cost(strategy))
            final.reviews
            |> should.equal(list.repeat(strategy.repeats, strategy.accounts))
            list.length(frames)
            |> should.equal(
              strategy.accounts + strategy.accounts * strategy.repeats + 2,
            )
          }
          False -> final.event |> should.equal(ring.BudgetRejected)
        }
      })
    })
  })
}

pub fn search_is_maximal_and_selects_cheapest_tie_test() {
  list.each([ring.EveryReview, ring.OnePerReviewer], fn(policy) {
    list.each([3, 10, 20, 24, 40], fn(budget) {
      let rules = ring.Rules(policy, budget, 80)
      let found = ring.search(rules)
      let score = ring.rating(ring.last(found.frames), policy)
      found |> should.equal(ring.search(rules))
      list.each(ring.strategies(), fn(candidate) {
        case ring.cost(candidate) <= budget {
          True -> {
            let other =
              ring.rating(ring.last(ring.run(rules, candidate, True)), policy)
            should.be_true(score >= other)
            case score == other {
              True ->
                should.be_true(
                  ring.cost(found.strategy) <= ring.cost(candidate),
                )
              False -> Nil
            }
          }
          False -> Nil
        }
      })
    })
  })
}
