import gleam/int
import gleam/list
import gleam/order

pub type Policy {
  Shortest
  Fair
}

pub type Rules {
  Rules(policy: Policy, cap: Int, horizon: Int)
}

pub type Strategy {
  Strategy(chunk: Int, burst: Int, delay: Int)
}

pub type Job {
  Job(id: Int, owner: Int, remaining: Int)
}

pub type Frame {
  Frame(
    tick: Int,
    served: Int,
    completed: List(Int),
    submitted: List(Int),
    queue: List(Job),
  )
}

pub type Search {
  Search(
    strategy: Strategy,
    frames: List(Frame),
    baseline: List(Frame),
    tested: Int,
    gain: Int,
  )
}

pub fn default_rules() -> Rules {
  Rules(Shortest, 4, 24)
}

pub fn honest() -> Strategy {
  Strategy(4, 1, 0)
}

pub fn initial() -> Frame {
  Frame(0, -1, [0, 0, 0, 0], [0, 0, 0, 0], [])
}

pub fn at(values: List(Int), index: Int) -> Int {
  list.drop(values, index) |> list.first |> result_or(0)
}

fn result_or(value: Result(a, b), fallback: a) -> a {
  case value {
    Ok(value) -> value
    Error(_) -> fallback
  }
}

fn add(values: List(Int), owner: Int, amount: Int) -> List(Int) {
  list.index_map(values, fn(value, index) {
    case index == owner {
      True -> value + amount
      False -> value
    }
  })
}

fn admit(frame: Frame, owner: Int, strategy: Strategy, cap: Int) -> Frame {
  case frame.tick < strategy.delay {
    True -> frame
    False -> {
      let waiting =
        list.filter(frame.queue, fn(job) { job.owner == owner }) |> list.length
      let slots = int.min(strategy.burst, int.max(0, cap - waiting))
      range(1, slots)
      |> list.fold(frame, fn(state, slot) {
        let amount = int.min(strategy.chunk, 12 - at(state.submitted, owner))
        case amount > 0 {
          False -> state
          True ->
            Frame(
              ..state,
              submitted: add(state.submitted, owner, amount),
              queue: list.append(state.queue, [
                Job(state.tick * 100 + owner * 10 + slot, owner, amount),
              ]),
            )
        }
      })
    }
  }
}

fn distance(owner: Int, cursor: Int) -> Int {
  { owner - cursor + 4 } % 4
}

fn compare_jobs(a: Job, b: Job, policy: Policy, cursor: Int) -> order.Order {
  let priority = case policy {
    Shortest -> int.compare(a.remaining, b.remaining)
    Fair -> order.Eq
  }
  case priority {
    order.Eq ->
      case int.compare(distance(a.owner, cursor), distance(b.owner, cursor)) {
        order.Eq -> int.compare(a.id, b.id)
        other -> other
      }
    other -> other
  }
}

pub fn step(frame: Frame, rules: Rules, strategy: Strategy) -> Frame {
  let frame =
    range(0, 3)
    |> list.fold(frame, fn(state, owner) {
      admit(
        state,
        owner,
        case owner == 3 {
          True -> strategy
          False -> honest()
        },
        rules.cap,
      )
    })
  let cursor = { frame.served + 1 } % 4
  let sorted =
    list.sort(frame.queue, fn(a, b) { compare_jobs(a, b, rules.policy, cursor) })
  case sorted {
    [] -> Frame(..frame, tick: frame.tick + 1, served: -1)
    [job, ..] -> {
      let queue =
        list.filter_map(frame.queue, fn(other) {
          case other.id == job.id {
            False -> Ok(other)
            True ->
              case other.remaining > 1 {
                True -> Ok(Job(..other, remaining: other.remaining - 1))
                False -> Error(Nil)
              }
          }
        })
      Frame(
        ..frame,
        tick: frame.tick + 1,
        served: job.owner,
        queue: queue,
        completed: add(frame.completed, job.owner, 1),
      )
    }
  }
}

pub fn run(rules: Rules, strategy: Strategy) -> List(Frame) {
  let #(_, frames) =
    range(1, rules.horizon)
    |> list.fold(#(initial(), [initial()]), fn(acc, _) {
      let #(previous, frames) = acc
      let next = step(previous, rules, strategy)
      #(next, [next, ..frames])
    })
  list.reverse(frames)
}

pub fn last(frames: List(Frame)) -> Frame {
  list.last(frames) |> result_or(initial())
}

pub fn frame_at(frames: List(Frame), tick: Int) -> Frame {
  list.drop(frames, tick) |> list.first |> result_or(initial())
}

pub fn score(frames: List(Frame)) -> Int {
  at(last(frames).completed, 3)
}

pub fn strategies() -> List(Strategy) {
  list.flat_map([1, 2, 3, 4], fn(chunk) {
    list.flat_map([1, 2, 4], fn(burst) {
      list.map([0, 2, 4], fn(delay) { Strategy(chunk, burst, delay) })
    })
  })
}

pub fn search(rules: Rules) -> Search {
  let baseline = run(rules, honest())
  let #(strategy, frames) =
    list.fold(strategies(), #(honest(), baseline), fn(best, strategy) {
      let frames = run(rules, strategy)
      case score(frames) > score(best.1) {
        True -> #(strategy, frames)
        False -> best
      }
    })
  Search(
    strategy,
    frames,
    baseline,
    list.length(strategies()),
    score(frames) - score(baseline),
  )
}

pub fn policy_name(policy: Policy) -> String {
  case policy {
    Shortest -> "Shortest job first"
    Fair -> "Fair rotation"
  }
}

pub fn owner_name(owner: Int) -> String {
  case owner {
    0 -> "Atlas"
    1 -> "Nova"
    2 -> "Moss"
    3 -> "Rogue"
    _ -> "Idle"
  }
}

pub fn range(start: Int, stop: Int) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..range(start + 1, stop)]
  }
}
