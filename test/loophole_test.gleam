import gleam/list
import gleeunit
import gleeunit/should
import loophole/engine

pub fn main() {
  gleeunit.main()
}

pub fn search_finds_real_advantage_test() {
  let result = engine.search(engine.default_rules())
  result.tested |> should.equal(36)
  should.be_true(result.gain > 0)
  engine.score(result.frames) |> should.equal(12)
  result.frames
  |> should.equal(engine.run(engine.default_rules(), result.strategy))
}

pub fn fair_rotation_removes_advantage_test() {
  let rules = engine.Rules(engine.Fair, 4, 24)
  let result = engine.search(rules)
  result.gain |> should.equal(0)
  engine.last(result.frames).completed |> should.equal([6, 6, 6, 6])
}

pub fn conservation_and_caps_across_search_space_test() {
  list.each([engine.Shortest, engine.Fair], fn(policy) {
    list.each([1, 4, 8], fn(cap) {
      list.each(engine.strategies(), fn(strategy) {
        let frames = engine.run(engine.Rules(policy, cap, 48), strategy)
        list.each(frames, fn(frame) {
          should.be_true(
            list.fold(frame.completed, 0, fn(a, b) { a + b }) <= frame.tick,
          )
          list.each(engine.range(0, 3), fn(owner) {
            let queued =
              list.filter(frame.queue, fn(job) { job.owner == owner })
            should.be_true(list.length(queued) <= cap)
            let pending =
              list.fold(queued, 0, fn(sum, job) { sum + job.remaining })
            should.equal(
              engine.at(frame.completed, owner) + pending,
              engine.at(frame.submitted, owner),
            )
            should.be_true(engine.at(frame.submitted, owner) <= 12)
          })
          let ids = list.map(frame.queue, fn(job) { job.id })
          list.unique(ids) |> should.equal(ids)
        })
        engine.last(frames).completed |> should.equal([12, 12, 12, 12])
      })
    })
  })
}

pub fn delay_is_respected_test() {
  let frames = engine.run(engine.default_rules(), engine.Strategy(1, 4, 4))
  engine.frame_at(frames, 4).submitted |> engine.at(3) |> should.equal(0)
  engine.frame_at(frames, 5).submitted |> engine.at(3) |> should.equal(4)
}

pub fn deterministic_replay_test() {
  let rules = engine.default_rules()
  let strategy = engine.Strategy(2, 4, 2)
  engine.run(rules, strategy) |> should.equal(engine.run(rules, strategy))
}

pub fn empty_queue_has_no_phantom_work_test() {
  let frames = engine.run(engine.Rules(engine.Fair, 4, 60), engine.honest())
  engine.last(frames).completed |> should.equal([12, 12, 12, 12])
  engine.last(frames).served |> should.equal(-1)
}
