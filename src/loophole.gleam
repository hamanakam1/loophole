import gleam/int
import gleam/json
import gleam/list
import gleam/string
import loophole/engine.{type Frame, type Rules, type Strategy, Fair, Shortest}
import lustre
import lustre/attribute as a
import lustre/element.{type Element, text}
import lustre/element/html as h
import lustre/event

@external(javascript, "./loophole/browser.mjs", "readHash")
fn read_hash() -> String

@external(javascript, "./loophole/browser.mjs", "writeHash")
fn write_hash(fragment: String) -> Nil

@external(javascript, "./loophole/browser.mjs", "downloadReceipt")
fn download_receipt(content: String) -> Nil

type Model {
  Model(
    rules: Rules,
    strategy: Strategy,
    frames: List(Frame),
    baseline: List(Frame),
    tick: Int,
    searched: Bool,
  )
}

type Msg {
  FindLoophole
  Repair
  PolicyChanged(String)
  CapChanged(String)
  HorizonChanged(String)
  Seek(Int)
  Scrub(String)
  Reset
  Export
}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn fresh(rules: Rules) -> Model {
  let frames = engine.run(rules, engine.honest())
  Model(rules, engine.honest(), frames, frames, rules.horizon, False)
}

fn searched(rules: Rules) -> Model {
  let result = engine.search(rules)
  Model(
    rules,
    result.strategy,
    result.frames,
    result.baseline,
    rules.horizon,
    True,
  )
}

fn parsed(value: String, fallback: Int, low: Int, high: Int) -> Int {
  case int.parse(value) {
    Ok(n) -> int.clamp(n, low, high)
    Error(_) -> fallback
  }
}

fn init(_) -> Model {
  case string.split(read_hash(), ":") {
    ["v1", policy, cap, horizon, found, tick] -> {
      let rules =
        engine.Rules(
          case policy {
            "fair" -> Fair
            _ -> Shortest
          },
          parsed(cap, 4, 1, 8),
          parsed(horizon, 24, 12, 48),
        )
      let model = case found {
        "searched" -> searched(rules)
        _ -> fresh(rules)
      }
      Model(..model, tick: parsed(tick, rules.horizon, 0, rules.horizon))
    }
    _ -> fresh(engine.default_rules())
  }
}

fn update(model: Model, msg: Msg) -> Model {
  let next = case msg {
    FindLoophole -> searched(model.rules)
    Repair -> searched(engine.Rules(..model.rules, policy: Fair))
    PolicyChanged(value) ->
      fresh(
        engine.Rules(..model.rules, policy: case value {
          "fair" -> Fair
          _ -> Shortest
        }),
      )
    CapChanged(value) ->
      fresh(engine.Rules(..model.rules, cap: parsed(value, 4, 1, 8)))
    HorizonChanged(value) ->
      fresh(engine.Rules(..model.rules, horizon: parsed(value, 24, 12, 48)))
    Seek(tick) -> Model(..model, tick: int.clamp(tick, 0, model.rules.horizon))
    Scrub(value) ->
      Model(..model, tick: parsed(value, 0, 0, model.rules.horizon))
    Reset -> fresh(engine.default_rules())
    Export -> {
      download_receipt(receipt(model))
      model
    }
  }
  write_hash(share_url(next))
  next
}

fn cls(value: String) {
  a.class(value)
}

fn attr(key: String, value: String) {
  a.attribute(key, value)
}

fn n(value: Int) {
  int.to_string(value)
}

fn label(value: String) {
  h.span([cls("eyebrow")], [text(value)])
}

fn pill(value: String, class: String) {
  h.span([cls("pill " <> class)], [text(value)])
}

fn policy_key(policy: engine.Policy) {
  case policy {
    Fair -> "fair"
    Shortest -> "shortest"
  }
}

fn gain(model: Model) {
  engine.score(model.frames) - engine.score(model.baseline)
}

fn share_url(model: Model) {
  "#v1:"
  <> policy_key(model.rules.policy)
  <> ":"
  <> n(model.rules.cap)
  <> ":"
  <> n(model.rules.horizon)
  <> ":"
  <> case model.searched {
    True -> "searched"
    False -> "baseline"
  }
  <> ":"
  <> n(model.tick)
}

fn view(model: Model) -> Element(Msg) {
  h.div([cls("shell")], [
    h.a([cls("skip-link"), a.href("#laboratory")], [text("Skip to laboratory")]),
    h.header([cls("topbar")], [
      h.a([a.href("./"), cls("brand"), attr("aria-label", "Loophole home")], [
        h.span([cls("brand-mark")], []),
        text("loophole"),
        h.span([cls("version")], [text("LAB / 001")]),
      ]),
      h.nav([attr("aria-label", "Main navigation")], [
        h.a([a.href("#how-it-works")], [text("How it works")]),
        h.a(
          [
            a.href("https://github.com/hamanakam1/loophole"),
            a.target("_blank"),
            a.rel("noopener noreferrer"),
            cls("source-link"),
          ],
          [text("Source code ↗")],
        ),
      ]),
    ]),
    h.main([], [
      h.section([cls("hero")], [
        h.div([], [
          label("AN ADVERSARIAL SYSTEMS PLAYGROUND"),
          h.h1([], [
            text("Good rules."),
            h.br([]),
            h.span([], [text("Bad incentives.")]),
          ]),
          h.p([cls("intro")], [
            text("Build a little world. Find the loophole. Change the rules."),
            h.br([]),
            text("A hands-on laboratory for the behavior you didn’t intend."),
          ]),
        ]),
        h.div([cls("hero-note")], [
          h.span([cls("status-dot")], []),
          text("RUNS ENTIRELY IN YOUR BROWSER"),
          h.div([cls("hero-meta")], [
            text("Gleam + Lustre"),
            h.span([], [text("/ MIT licensed / No API keys")]),
          ]),
        ]),
      ]),
      h.div([cls("lab-heading"), a.id("laboratory")], [
        h.div([], [
          label("EXPERIMENT 01"),
          h.h2([], [text("The shared compute problem")]),
        ]),
        pill("4 users · 1 processor · finite resources", "neutral"),
      ]),
      h.div([cls("laboratory")], [
        rules_panel(model),
        arena(model),
        results_panel(model),
      ]),
      timeline(model),
      h.div([cls("lower-grid")], [explanation(model), methodology()]),
    ]),
    h.footer([], [
      h.span([], [
        text("loophole"),
        h.span([cls("muted")], [text(" / small worlds, consequential rules.")]),
      ]),
      h.span([], [
        text("Open source. Open to being wrong."),
        h.a(
          [a.href("https://github.com/hamanakam1/loophole/blob/main/LICENSE")],
          [text("MIT ↗")],
        ),
      ]),
    ]),
  ])
}

fn rules_panel(model: Model) -> Element(Msg) {
  h.aside([cls("panel rules")], [
    h.div([cls("panel-title")], [
      label("01 / SET THE RULES"),
      h.span([cls("tiny-icon")], [text("≡")]),
    ]),
    h.h3([], [text("Who gets the next turn?")]),
    h.p([cls("muted small")], [
      text(
        "Everyone needs 12 compute units. Three users play normally. One searches for an advantage.",
      ),
    ]),
    h.label([a.for("policy")], [text("Scheduling policy")]),
    h.select([a.id("policy"), event.on_change(PolicyChanged)], [
      h.option(
        [a.value("shortest"), a.selected(model.rules.policy == Shortest)],
        "Shortest job first",
      ),
      h.option(
        [a.value("fair"), a.selected(model.rules.policy == Fair)],
        "Fair rotation",
      ),
    ]),
    h.p([cls("field-help")], [
      text(case model.rules.policy {
        Shortest -> "Small jobs jump ahead. Sounds efficient."
        Fair -> "Rotate between users, regardless of job size."
      }),
    ]),
    h.div([cls("range-heading")], [
      h.label([a.for("cap")], [text("Queue cap per user")]),
      h.output([a.for("cap")], [text(n(model.rules.cap) <> " jobs")]),
    ]),
    h.input([
      a.id("cap"),
      a.type_("range"),
      a.min("1"),
      a.max("8"),
      a.value(n(model.rules.cap)),
      event.on_input(CapChanged),
    ]),
    h.div([cls("range-ends")], [text("1"), h.span([], [text("8")])]),
    h.div([cls("range-heading")], [
      h.label([a.for("horizon")], [text("Observation window")]),
      h.output([a.for("horizon")], [text(n(model.rules.horizon) <> " ticks")]),
    ]),
    h.input([
      a.id("horizon"),
      a.type_("range"),
      a.min("12"),
      a.max("48"),
      a.step("12"),
      a.value(n(model.rules.horizon)),
      event.on_input(HorizonChanged),
    ]),
    h.div([cls("range-ends")], [text("12"), h.span([], [text("48")])]),
    h.button([cls("primary"), event.on_click(FindLoophole)], [
      text("Find a loophole"),
      h.span([], [text("↗")]),
    ]),
    h.p([cls("search-note")], [text("36 strategies. Deterministic search.")]),
    h.button([cls("text-button"), event.on_click(Reset)], [
      text("↺ Reset experiment"),
    ]),
  ])
}

fn svg(
  tag: String,
  attributes: List(a.Attribute(Msg)),
  children: List(Element(Msg)),
) {
  element.namespaced("http://www.w3.org/2000/svg", tag, attributes, children)
}

fn circle(x: Int, y: Int, r: Int, class: String) {
  svg(
    "circle",
    [attr("cx", n(x)), attr("cy", n(y)), attr("r", n(r)), cls(class)],
    [],
  )
}

fn svg_text(x: Int, y: Int, value: String, class: String) {
  svg(
    "text",
    [
      attr("x", n(x)),
      attr("y", n(y)),
      cls(class),
      attr("text-anchor", "middle"),
    ],
    [text(value)],
  )
}

fn color(owner: Int) {
  case owner {
    0 -> "atlas"
    1 -> "nova"
    2 -> "moss"
    _ -> "rogue"
  }
}

fn arena(model: Model) -> Element(Msg) {
  let frame = engine.frame_at(model.frames, model.tick)
  h.section([cls("panel arena")], [
    h.div([cls("panel-title")], [
      label("02 / WATCH THE SYSTEM"),
      pill(
        case model.searched {
          True -> "SEARCH COMPLETE"
          False -> "BASELINE RUN"
        },
        case model.searched {
          True -> "lavender"
          False -> "neutral"
        },
      ),
    ]),
    h.div([cls("arena-caption")], [
      h.span([], [
        text(case model.searched {
          True -> "One user. A different strategy."
          False -> "Same workload. Same strategy."
        }),
      ]),
      h.span([cls("mono")], [text("t = " <> n(model.tick))]),
    ]),
    svg(
      "svg",
      [
        attr("viewBox", "0 0 600 410"),
        cls("world"),
        attr("role", "img"),
        attr(
          "aria-label",
          "Compute allocation at tick "
            <> n(model.tick)
            <> ". Atlas "
            <> n(engine.at(frame.completed, 0))
            <> ", Nova "
            <> n(engine.at(frame.completed, 1))
            <> ", Moss "
            <> n(engine.at(frame.completed, 2))
            <> ", Rogue "
            <> n(engine.at(frame.completed, 3))
            <> " units.",
        ),
      ],
      [
        svg("defs", [], [
          svg(
            "pattern",
            [
              attr("id", "dots"),
              attr("width", "22"),
              attr("height", "22"),
              attr("patternUnits", "userSpaceOnUse"),
            ],
            [circle(1, 1, 1, "grid-dot")],
          ),
          svg("radialGradient", [attr("id", "glow")], [
            svg(
              "stop",
              [
                attr("offset", "0%"),
                attr("stop-color", "#bda7ff"),
                attr("stop-opacity", "0.13"),
              ],
              [],
            ),
            svg(
              "stop",
              [
                attr("offset", "100%"),
                attr("stop-color", "#bda7ff"),
                attr("stop-opacity", "0"),
              ],
              [],
            ),
          ]),
        ]),
        svg(
          "rect",
          [
            attr("width", "600"),
            attr("height", "410"),
            attr("fill", "url(#dots)"),
          ],
          [],
        ),
        svg(
          "circle",
          [
            attr("cx", "300"),
            attr("cy", "200"),
            attr("r", "195"),
            attr("fill", "url(#glow)"),
          ],
          [],
        ),
        circle(300, 200, 150, "orbit outer"),
        circle(300, 200, 100, "orbit"),
        svg(
          "path",
          [
            attr(
              "d",
              "M128 100 Q300 50 300 200 M472 100 Q300 50 300 200 M128 300 Q300 350 300 200 M472 300 Q300 350 300 200",
            ),
            cls("connection"),
          ],
          [],
        ),
        circle(300, 200, 56, "processor"),
        circle(300, 200, 66, "processor-ring"),
        svg_text(300, 191, n(model.tick), "center-count"),
        svg_text(300, 217, "TICKS ELAPSED", "center-label"),
        actor(frame, 0, 128, 100),
        actor(frame, 1, 472, 100),
        actor(frame, 2, 128, 300),
        actor(frame, 3, 472, 300),
        svg_text(
          300,
          385,
          "ONE PROCESSOR · ONE UNIT PER TICK",
          "world-footnote",
        ),
      ],
    ),
    h.div([cls("legend")], [
      h.span([], [h.i([cls("legend-dot friendly")], []), text("Normal users")]),
      h.span([], [
        h.i([cls("legend-dot adversary")], []),
        text("Strategic user"),
      ]),
      h.span([cls("muted")], [text("Dots = queued jobs")]),
    ]),
    h.div([cls("service-status")], [
      h.span([cls("status-dot " <> color(frame.served))], []),
      text(case frame.served {
        -1 -> "Ready to replay the allocation"
        owner ->
          engine.owner_name(owner)
          <> " received compute at tick "
          <> n(frame.tick)
      }),
      h.span([cls("mono muted")], [
        text(n(list.length(frame.queue)) <> " queued"),
      ]),
    ]),
  ])
}

fn actor(frame: Frame, owner: Int, x: Int, y: Int) -> Element(Msg) {
  let active = case frame.served == owner {
    True -> " active"
    False -> ""
  }
  let pending =
    list.filter(frame.queue, fn(job) { job.owner == owner }) |> list.length
  svg("g", [cls("actor " <> color(owner) <> active)], [
    circle(x, y, 39, "actor-halo"),
    circle(x, y, 30, "actor-disc"),
    svg_text(x, y + 7, n(engine.at(frame.completed, owner)), "actor-count"),
    svg_text(
      x,
      y - 51,
      string.uppercase(engine.owner_name(owner)),
      "actor-name",
    ),
    svg_text(x, y + 54, "of 12 units", "actor-caption"),
    svg(
      "g",
      [],
      list.map(engine.range(1, pending), fn(i) {
        circle(x - { pending - 1 } * 5 + { i - 1 } * 10, y + 70, 2, "queue-dot")
      }),
    ),
  ])
}

fn results_panel(model: Model) -> Element(Msg) {
  let score = engine.score(model.frames)
  let base = engine.score(model.baseline)
  let found = model.searched && gain(model) > 0
  h.aside([cls("panel results"), attr("aria-live", "polite")], [
    h.div([cls("panel-title")], [label("03 / READ THE OUTCOME")]),
    pill(
      case model.searched {
        False -> "AWAITING SEARCH"
        True ->
          case found {
            True -> "LOOPHOLE FOUND"
            False -> "NO GAIN FOUND"
          }
      },
      case found {
        True -> "orange"
        False -> "neutral"
      },
    ),
    h.h3([cls("outcome-title")], [
      text(case model.searched {
        False -> "What could go wrong?"
        True ->
          case found {
            True -> "Small jobs. Big advantage."
            False -> "A level playing field."
          }
      }),
    ]),
    h.p([cls("muted small")], [
      text(case model.searched {
        False ->
          "Let Rogue search for a better allocation without changing its total workload."
        True ->
          case found {
            True ->
              "Rogue changes how it submits work. The scheduler rewards the strategy."
            False ->
              "None of the 36 tested strategies improves Rogue’s allocation in this window."
          }
      }),
    ]),
    h.div([cls("gain-number")], [
      text(case found {
        True -> "+" <> n(gain(model))
        False -> "0"
      }),
      h.span([], [text("extra units")]),
    ]),
    h.div([cls("comparison")], [
      comparison_bar("Baseline", base, "base"),
      comparison_bar(
        case model.searched {
          True -> "Best found"
          False -> "Current"
        },
        score,
        "best",
      ),
    ]),
    h.div([cls("strategy")], [
      label(case model.searched {
        True -> "BEST STRATEGY FOUND"
        False -> "BASELINE STRATEGY"
      }),
      h.div([], [
        h.span([], [text("Job size")]),
        h.strong([], [
          text(
            n(model.strategy.chunk)
            <> case model.strategy.chunk {
              1 -> " unit"
              _ -> " units"
            },
          ),
        ]),
      ]),
      h.div([], [
        h.span([], [text("Submission burst")]),
        h.strong([], [text(n(model.strategy.burst) <> "/tick")]),
      ]),
      h.div([], [
        h.span([], [text("Start delay")]),
        h.strong([], [text(n(model.strategy.delay) <> " ticks")]),
      ]),
    ]),
    h.button([cls("secondary"), event.on_click(Repair)], [
      text("Try fair rotation"),
      h.span([], [text("→")]),
    ]),
    h.p([cls("search-note")], [
      text("Re-runs all 36 strategies with the new rule."),
    ]),
  ])
}

fn comparison_bar(title: String, value: Int, class: String) {
  h.div([cls("comparison-row")], [
    h.span([], [text(title)]),
    h.div([cls("bar-track")], [
      h.div(
        [cls("bar " <> class), a.style("width", n(value * 100 / 12) <> "%")],
        [],
      ),
    ]),
    h.strong([], [text(n(value))]),
  ])
}

fn timeline(model: Model) -> Element(Msg) {
  h.section([cls("panel timeline")], [
    h.div([cls("timeline-heading")], [
      h.div([], [
        label("THE REPLAY"),
        h.span([cls("muted small")], [
          text("Every tile is one compute unit. Select any tick."),
        ]),
      ]),
      h.div([cls("replay-actions")], [
        h.button([event.on_click(Export), cls("text-button")], [
          text("↓ Export JSON"),
        ]),
        h.a(
          [
            a.href(share_url(model)),
            a.target("_blank"),
            a.rel("noopener"),
            cls("text-button"),
          ],
          [text("Open replay link ↗")],
        ),
      ]),
    ]),
    h.div(
      [cls("timeline-track"), attr("aria-label", "Allocation timeline")],
      list.map(list.drop(model.frames, 1), fn(frame) {
        h.button(
          [
            cls(
              "tick "
              <> color(frame.served)
              <> case frame.tick == model.tick {
                True -> " selected"
                False -> ""
              },
            ),
            event.on_click(Seek(frame.tick)),
            attr(
              "aria-label",
              "Tick "
                <> n(frame.tick)
                <> ": "
                <> engine.owner_name(frame.served),
            ),
            attr("aria-pressed", case frame.tick == model.tick {
              True -> "true"
              False -> "false"
            }),
            a.title(
              "Tick "
              <> n(frame.tick)
              <> " · "
              <> engine.owner_name(frame.served),
            ),
          ],
          [text(string.slice(engine.owner_name(frame.served), 0, 1))],
        )
      }),
    ),
    h.div([cls("playback")], [
      h.button(
        [
          cls("transport"),
          event.on_click(Seek(0)),
          a.disabled(model.tick == 0),
          attr("aria-label", "Rewind to start"),
        ],
        [text("↤")],
      ),
      h.button(
        [
          cls("transport"),
          event.on_click(Seek(model.tick - 1)),
          a.disabled(model.tick == 0),
          attr("aria-label", "Previous tick"),
        ],
        [text("←")],
      ),
      h.button(
        [
          cls("transport"),
          event.on_click(Seek(model.tick + 1)),
          a.disabled(model.tick == model.rules.horizon),
          attr("aria-label", "Next tick"),
        ],
        [text("→")],
      ),
      h.input([
        a.type_("range"),
        a.min("0"),
        a.max(n(model.rules.horizon)),
        a.value(n(model.tick)),
        event.on_input(Scrub),
        attr("aria-label", "Replay tick"),
      ]),
      h.span([cls("mono")], [
        text(n(model.tick) <> " / " <> n(model.rules.horizon)),
      ]),
    ]),
  ])
}

fn explanation(model: Model) -> Element(Msg) {
  h.section([cls("explanation"), a.id("how-it-works")], [
    label("THE IDEA BEHIND THE EXPERIMENT"),
    h.h2([], [
      text("Optimize the rules."),
      h.br([]),
      h.span([cls("muted")], [text("Or someone will optimize around them.")]),
    ]),
    h.p([], [
      text(case model.rules.policy {
        Shortest ->
          "A short-job policy rewards smaller requests. Rogue can split the same 12 units into tiny jobs and move ahead of everyone else. A queue cap limits simultaneous requests, but it does not remove the incentive to split."
        Fair ->
          "Fair rotation allocates one unit at a time to each user with pending work. Splitting a job no longer buys more turns. This relies on stable user identities; creating extra identities is outside this model."
      }),
    ]),
  ])
}

fn methodology() -> Element(Msg) {
  h.details([cls("methodology")], [
    h.summary([], [text("Inside this tiny world"), h.span([], [text("+")])]),
    h.div([cls("method-body")], [
      h.p([], [
        text(
          "Four users each need 12 units. Atlas, Nova and Moss submit 4-unit jobs, at most one per tick. Rogue searches job sizes 1–4, bursts of 1, 2 or 4, and delays of 0, 2 or 4 ticks.",
        ),
      ]),
      h.p([], [
        text(
          "Each tick admits jobs up to the queue cap, then serves one unit. Shortest-job ties rotate between users; fair rotation ignores job size. Work can be interrupted between ticks. Pending jobs retain their remaining work.",
        ),
      ]),
      h.p([], [
        text(
          "The result is an exhaustive comparison of these 36 fixed strategies, not a proof against every possible strategy. Counts measure allocated compute, not completed jobs. At 48 ticks everyone finishes, so early advantage disappears from the final total.",
        ),
      ]),
      h.p([], [
        text(
          "No AI model, randomness, tracking, backend or real infrastructure access. Everything here is a simulation.",
        ),
      ]),
    ]),
  ])
}

fn receipt(model: Model) -> String {
  json.object([
    #("schema", json.string("loophole.replay.v1")),
    #("version", json.string("0.1.0")),
    #("policy", json.string(policy_key(model.rules.policy))),
    #("queue_cap", json.int(model.rules.cap)),
    #("horizon", json.int(model.rules.horizon)),
    #("searched", json.bool(model.searched)),
    #(
      "strategies_tested",
      json.int(case model.searched {
        True -> 36
        False -> 0
      }),
    ),
    #(
      "strategy",
      json.object([
        #("chunk", json.int(model.strategy.chunk)),
        #("burst", json.int(model.strategy.burst)),
        #("delay", json.int(model.strategy.delay)),
      ]),
    ),
    #("baseline_units", json.int(engine.score(model.baseline))),
    #("rogue_units", json.int(engine.score(model.frames))),
    #("gain", json.int(gain(model))),
    #("replay_fragment", json.string(share_url(model))),
    #(
      "frames",
      json.array(model.frames, fn(frame) {
        json.object([
          #("tick", json.int(frame.tick)),
          #("served", json.string(engine.owner_name(frame.served))),
          #("allocated", json.array(frame.completed, json.int)),
          #("submitted", json.array(frame.submitted, json.int)),
          #(
            "queue",
            json.array(frame.queue, fn(job) {
              json.object([
                #("id", json.int(job.id)),
                #("owner", json.string(engine.owner_name(job.owner))),
                #("remaining", json.int(job.remaining)),
              ])
            }),
          ),
        ])
      }),
    ),
  ])
  |> json.to_string
}
