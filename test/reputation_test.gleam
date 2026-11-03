import gleam/int
import gleam/list
import gleeunit/should
import loophole/reputation as rep

pub fn cheap_history_unlocks_large_loss_test() {
  let found = rep.search(rep.default_rules())
  found.tested |> should.equal(48)
  found.strategy |> should.equal(rep.Strategy(4, 1, 64))
  rep.rating(rep.frame_at(found.frames, 4)) |> should.equal(83)
  let final = rep.last(found.frames)
  final.outcome |> should.equal(rep.Defaulted)
  final.seized |> should.equal(4)
  final.loss |> should.equal(60)
  rep.rating(final) |> should.equal(71)
  rep.last(found.baseline).loss |> should.equal(0)
}

pub fn collateral_rule_rejects_same_large_request_test() {
  let found = rep.search(rep.Rules(rep.BondBacked, 80, 64))
  found.strategy |> should.equal(rep.Strategy(4, 1, 64))
  rep.last(found.frames).outcome |> should.equal(rep.BondRejected)
  rep.last(found.frames).bond |> should.equal(4)
  rep.last(found.frames).loss |> should.equal(0)
  // Honest users with the same small history are rejected too.
  rep.last(found.baseline).outcome |> should.equal(rep.BondRejected)
}

pub fn collateral_covers_accepted_default_test() {
  let final =
    rep.run(rep.Rules(rep.BondBacked, 80, 64), rep.Strategy(8, 4, 16), True)
    |> rep.last
  final.outcome |> should.equal(rep.Defaulted)
  final.seized |> should.equal(16)
  final.bond |> should.equal(16)
  final.loss |> should.equal(0)
}

pub fn rating_and_ceiling_gates_test() {
  rep.run(rep.default_rules(), rep.Strategy(2, 1, 64), True)
  |> rep.last
  |> fn(frame) { frame.outcome }
  |> should.equal(rep.RatingRejected)
  rep.run(rep.Rules(rep.RatingOnly, 80, 16), rep.Strategy(4, 1, 64), True)
  |> rep.last
  |> fn(frame) { frame.outcome }
  |> should.equal(rep.CeilingRejected)
  rep.search(rep.Rules(rep.RatingOnly, 95, 64)).frames
  |> rep.last
  |> fn(frame) { frame.loss }
  |> should.equal(0)
}

pub fn raising_rating_threshold_still_allows_loss_test() {
  let found = rep.search(rep.Rules(rep.RatingOnly, 90, 64))
  found.strategy.history |> should.equal(8)
  rep.last(found.frames).loss |> should.equal(56)
}

pub fn all_reputation_strategies_conserve_collateral_test() {
  list.each([rep.RatingOnly, rep.BondBacked], fn(policy) {
    list.each([70, 80, 90, 95], fn(threshold) {
      list.each([8, 32, 64], fn(ceiling) {
        let rules = rep.Rules(policy, threshold, ceiling)
        list.each(rep.strategies(), fn(strategy) {
          list.each([False, True], fn(betray) {
            let frames = rep.run(rules, strategy, betray)
            list.length(frames) |> should.equal(strategy.history + 2)
            list.each(frames, fn(frame) {
              should.equal(frame.bond + frame.seized, frame.delivered)
              should.be_true(
                frame.bond >= 0 && frame.loss >= 0 && frame.seized >= 0,
              )
              should.be_true(rep.rating(frame) >= 0 && rep.rating(frame) <= 100)
              case frame.outcome {
                rep.Defaulted -> {
                  should.equal(frame.loss + frame.seized, strategy.request)
                  should.equal(
                    frame.seized,
                    int.min(strategy.history * strategy.small, strategy.request),
                  )
                }
                _ -> frame.loss |> should.equal(0)
              }
            })
            case policy {
              rep.BondBacked -> rep.last(frames).loss |> should.equal(0)
              _ -> Nil
            }
            case betray {
              False -> rep.last(frames).loss |> should.equal(0)
              True -> Nil
            }
          })
        })
      })
    })
  })
}

pub fn search_is_deterministic_and_maximal_test() {
  list.each([rep.RatingOnly, rep.BondBacked], fn(policy) {
    let rules = rep.Rules(policy, 80, 64)
    let found = rep.search(rules)
    found |> should.equal(rep.search(rules))
    list.each(rep.strategies(), fn(candidate) {
      should.be_true(
        rep.last(found.frames).loss
        >= rep.last(rep.run(rules, candidate, True)).loss,
      )
    })
  })
}
