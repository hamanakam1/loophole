import gleam/int
import gleam/json
import gleam/list
import gleam/string
import loophole/reputation as rep
import lustre/attribute as a
import lustre/element.{type Element, text}
import lustre/element/html as h
import lustre/event

pub type Model {
  Model(
    rules: rep.Rules,
    strategy: rep.Strategy,
    frames: List(rep.Frame),
    baseline: List(rep.Frame),
    step: Int,
    searched: Bool,
  )
}

pub type Msg {
  Search
  Repair
  Policy(String)
  Threshold(String)
  Ceiling(String)
  Seek(Int)
  Scrub(String)
  Reset
  Export
}

fn parsed(value: String, fallback: Int, low: Int, high: Int) {
  case int.parse(value) {
    Ok(n) -> int.clamp(n, low, high)
    Error(_) -> fallback
  }
}

fn fresh(rules: rep.Rules) {
  let strategy = rep.default_strategy()
  let frames = rep.run(rules, strategy, False)
  Model(rules, strategy, frames, frames, rep.last(frames).step, False)
}

fn searched(rules: rep.Rules) {
  let found = rep.search(rules)
  Model(
    rules,
    found.strategy,
    found.frames,
    found.baseline,
    rep.last(found.frames).step,
    True,
  )
}

pub fn init(fragment: String) -> Model {
  case string.split(fragment, ":") {
    ["rep1", policy, threshold, ceiling, mode, step] -> {
      let rules =
        rep.Rules(
          case policy {
            "bond" -> rep.BondBacked
            _ -> rep.RatingOnly
          },
          parsed(threshold, 80, 50, 99),
          parsed(ceiling, 64, 8, 64),
        )
      let model = case mode {
        "searched" -> searched(rules)
        _ -> fresh(rules)
      }
      Model(
        ..model,
        step: parsed(
          step,
          rep.last(model.frames).step,
          0,
          rep.last(model.frames).step,
        ),
      )
    }
    _ -> fresh(rep.default_rules())
  }
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Search -> searched(model.rules)
    Repair -> searched(rep.Rules(..model.rules, policy: rep.BondBacked))
    Policy(value) ->
      fresh(
        rep.Rules(..model.rules, policy: case value {
          "bond" -> rep.BondBacked
          _ -> rep.RatingOnly
        }),
      )
    Threshold(value) ->
      fresh(rep.Rules(..model.rules, threshold: parsed(value, 80, 50, 99)))
    Ceiling(value) ->
      fresh(rep.Rules(..model.rules, ceiling: parsed(value, 64, 8, 64)))
    Seek(step) ->
      Model(..model, step: int.clamp(step, 0, rep.last(model.frames).step))
    Scrub(value) ->
      Model(..model, step: parsed(value, 0, 0, rep.last(model.frames).step))
    Reset -> fresh(rep.default_rules())
    Export -> model
  }
}

pub fn share_url(model: Model) -> String {
  "#rep1:"
  <> rep.policy_key(model.rules.policy)
  <> ":"
  <> n(model.rules.threshold)
  <> ":"
  <> n(model.rules.ceiling)
  <> ":"
  <> case model.searched {
    True -> "searched"
    False -> "baseline"
  }
  <> ":"
  <> n(model.step)
}

fn n(value: Int) {
  int.to_string(value)
}

fn cls(value: String) {
  a.class(value)
}

fn attr(key: String, value: String) {
  a.attribute(key, value)
}

fn label(value: String) {
  h.span([cls("eyebrow")], [text(value)])
}

fn pill(value: String, class: String) {
  h.span([cls("pill " <> class)], [text(value)])
}

fn units(value: Int) {
  n(value)
  <> case value {
    1 -> " credit"
    _ -> " credits"
  }
}

pub fn view(model: Model) -> Element(Msg) {
  h.div([cls("reputation-experiment")], [
    h.div([cls("lab-heading"), a.id("laboratory")], [
      h.div([], [
        label("EXPERIMENT 02"),
        h.h2([], [text("The reputation trap")]),
      ]),
      pill("Small favors · big promises · misplaced trust", "neutral"),
    ]),
    h.div([cls("laboratory")], [
      rules_panel(model),
      arena(model),
      results(model),
    ]),
    timeline(model),
    h.div([cls("lower-grid")], [
      h.section([cls("explanation"), a.id("how-it-works")], [
        label("THE IDEA BEHIND THE EXPERIMENT"),
        h.h2([], [
          text("A good history."),
          h.br([]),
          h.span([cls("muted")], [text("A promise it cannot cover.")]),
        ]),
        h.p([], [
          text(case model.rules.policy {
            rep.RatingOnly ->
              "A count-based rating treats a tiny delivery like a large one. Rogue completes cheap work, earns a trusted score, and defaults on a bigger request. Raising the rating threshold makes the setup longer, but can leave the mismatch intact."
            rep.BondBacked ->
              "Requiring collateral ties the size of a promise to funds already locked. The same large request is rejected, and any accepted default is fully covered in this model. The tradeoff: an honest seller with this same history is also refused the large request."
          }),
        ]),
      ]),
      h.details([cls("methodology")], [
        h.summary([], [
          text("What this reputation model assumes"),
          h.span([], [text("+")]),
        ]),
        h.div([cls("method-body")], [
          h.p([], [
            text(
              "One seller first completes prepaid deliveries. Each delivered credit is locked as collateral. These small deliveries cannot create an uncovered loss. The final request is the only risky transaction.",
            ),
          ]),
          h.p([], [
            text(
              "Rating = 100 × (successful deliveries + 1) / (all outcomes + 2), rounded down. Each delivery counts once regardless of size. A rejection is not an outcome for the rating.",
            ),
          ]),
          h.p([], [
            text(
              "Search covers 1, 2, 4 or 8 small deliveries; sizes 1, 2 or 4; and final requests of 8, 16, 32 or 64 credits. That is 48 fixed strategies. Loss is the defaulted request minus seized collateral, never less than zero.",
            ),
          ]),
          h.p([], [
            text(
              "The honest baseline uses the same history and request but fulfills the final order if approved. Mitigation rechecks all 48 strategies and retains the rating-only attack when losses tie at zero.",
            ),
          ]),
          h.p([], [
            text(
              "Stable identity, enforceable collateral, instant settlement, and accurate outcomes are assumed. No fake reviews, collusion, identity resets, recovery costs, or real money. This is a toy model, not a fraud detector or a proof against all attacks.",
            ),
          ]),
        ]),
      ]),
    ]),
  ])
}

fn rules_panel(model: Model) {
  h.aside([cls("panel rules")], [
    h.div([cls("panel-title")], [
      label("01 / SET THE TRUST RULES"),
      h.span([cls("tiny-icon")], [text("≡")]),
    ]),
    h.h3([], [text("What is a good rating worth?")]),
    h.p([cls("muted small")], [
      text(
        "A seller earns a reputation on small deliveries, then asks to be trusted with a bigger order.",
      ),
    ]),
    h.label([a.for("trust-policy")], [text("Approval policy")]),
    h.select([a.id("trust-policy"), event.on_change(Policy)], [
      h.option(
        [a.value("rating"), a.selected(model.rules.policy == rep.RatingOnly)],
        "Rating only",
      ),
      h.option(
        [a.value("bond"), a.selected(model.rules.policy == rep.BondBacked)],
        "Rating + collateral",
      ),
    ]),
    h.p([cls("field-help")], [
      text(case model.rules.policy {
        rep.RatingOnly -> "Approve on score. Size is only capped globally."
        rep.BondBacked -> "Also require locked collateral to cover the request."
      }),
    ]),
    h.div([cls("range-heading")], [
      h.label([a.for("trust-threshold")], [text("Minimum rating")]),
      h.output([a.for("trust-threshold")], [
        text(n(model.rules.threshold) <> "/100"),
      ]),
    ]),
    h.input([
      a.id("trust-threshold"),
      a.type_("range"),
      a.min("50"),
      a.max("99"),
      a.value(n(model.rules.threshold)),
      event.on_input(Threshold),
    ]),
    h.div([cls("range-ends")], [text("50"), h.span([], [text("99")])]),
    h.div([cls("range-heading")], [
      h.label([a.for("request-ceiling")], [text("Maximum request")]),
      h.output([a.for("request-ceiling")], [text(units(model.rules.ceiling))]),
    ]),
    h.input([
      a.id("request-ceiling"),
      a.type_("range"),
      a.min("8"),
      a.max("64"),
      a.value(n(model.rules.ceiling)),
      event.on_input(Ceiling),
    ]),
    h.div([cls("range-ends")], [text("8"), h.span([], [text("64")])]),
    h.button([cls("primary"), event.on_click(Search)], [
      text("Find a trust exploit"),
      h.span([], [text("↗")]),
    ]),
    h.p([cls("search-note")], [
      text("48 strategies. Real transitions, in a toy world."),
    ]),
    h.button([cls("text-button"), event.on_click(Reset)], [
      text("↺ Reset reputation experiment"),
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

fn point_x(step: Int, last: Int) {
  55 + step * 490 / last
}

fn point_y(frame: rep.Frame) {
  378 - rep.rating(frame) * 13 / 10
}

fn points(frames: List(rep.Frame), last: Int) {
  list.map(frames, fn(frame) {
    n(point_x(frame.step, last)) <> "," <> n(point_y(frame))
  })
  |> string.join(" ")
}

fn arena(model: Model) {
  let frame = rep.frame_at(model.frames, model.step)
  let final_step = rep.last(model.frames).step
  let score = rep.rating(frame)
  let before = rep.frame_at(model.frames, model.strategy.history)
  h.section([cls("panel arena trust-arena")], [
    h.div([cls("panel-title")], [
      label("02 / WATCH TRUST ACCUMULATE"),
      pill(
        case model.searched {
          True -> "SEARCH COMPLETE"
          False -> "HONEST BASELINE"
        },
        "lavender",
      ),
    ]),
    h.div([cls("arena-caption")], [
      h.span([], [text("A good score. A much larger promise.")]),
      h.span([cls("mono")], [text("step " <> n(model.step))]),
    ]),
    svg(
      "svg",
      [
        attr("viewBox", "0 0 600 420"),
        cls("world trust-world"),
        attr("role", "img"),
        attr(
          "aria-label",
          "Seller at step "
            <> n(model.step)
            <> ": rating "
            <> n(score)
            <> ", collateral "
            <> n(frame.bond)
            <> ", uncovered loss "
            <> n(frame.loss)
            <> ". "
            <> rep.outcome_label(frame.outcome),
        ),
      ],
      [
        svg(
          "circle",
          [
            attr("cx", "300"),
            attr("cy", "114"),
            attr("r", "90"),
            cls("orbit outer"),
          ],
          [],
        ),
        svg(
          "circle",
          [
            attr("cx", "300"),
            attr("cy", "114"),
            attr("r", "68"),
            cls("trust-ring-track"),
          ],
          [],
        ),
        svg(
          "circle",
          [
            attr("cx", "300"),
            attr("cy", "114"),
            attr("r", "68"),
            cls("trust-ring"),
            attr("pathLength", "100"),
            attr("stroke-dasharray", n(score) <> " 100"),
            attr("transform", "rotate(-90 300 114)"),
          ],
          [],
        ),
        svg_text(300, 91, "ROGUE’S RATING", "center-label"),
        svg_text(300, 129, n(score), "center-count"),
        svg_text(300, 152, "OUT OF 100", "center-label"),
        svg_text(105, 94, n(frame.delivered), "trust-value"),
        svg_text(105, 119, "DELIVERED", "center-label"),
        svg_text(105, 139, "credits", "actor-caption"),
        svg_text(495, 94, n(frame.bond), "trust-value bond-value"),
        svg_text(495, 119, "COLLATERAL", "center-label"),
        svg_text(495, 139, "credits still locked", "actor-caption"),
        svg_text(
          300,
          222,
          "RATING OVER THE TRANSACTION HISTORY",
          "world-footnote",
        ),
        svg(
          "line",
          [
            attr("x1", "55"),
            attr("x2", "545"),
            attr("y1", "378"),
            attr("y2", "378"),
            cls("orbit"),
          ],
          [],
        ),
        svg(
          "line",
          [
            attr("x1", "55"),
            attr("x2", "545"),
            attr("y1", n(378 - model.rules.threshold * 13 / 10)),
            attr("y2", n(378 - model.rules.threshold * 13 / 10)),
            cls("threshold-line"),
          ],
          [],
        ),
        svg_text(
          300,
          245,
          "APPROVAL THRESHOLD " <> n(model.rules.threshold),
          "threshold-label",
        ),
        svg(
          "polyline",
          [
            attr("points", points(model.frames, final_step)),
            cls("trust-line future"),
          ],
          [],
        ),
        svg(
          "polyline",
          [
            attr(
              "points",
              points(list.take(model.frames, model.step + 1), final_step),
            ),
            cls("trust-line"),
          ],
          [],
        ),
        svg(
          "g",
          [],
          list.map(model.frames, fn(item) {
            svg(
              "circle",
              [
                attr("cx", n(point_x(item.step, final_step))),
                attr("cy", n(point_y(item))),
                attr("r", case item.step == model.step {
                  True -> "7"
                  False -> "4"
                }),
                cls(
                  "trust-point "
                  <> case item.outcome {
                    rep.Defaulted -> "default-point"
                    _ -> ""
                  },
                ),
                attr("opacity", case item.step <= model.step {
                  True -> "1"
                  False -> ".25"
                }),
              ],
              [],
            )
          }),
        ),
        svg_text(55, 403, "NEW SELLER", "world-footnote"),
        svg_text(490, 403, "FINAL REQUEST", "world-footnote"),
      ],
    ),
    h.div([cls("trust-summary")], [
      h.span([], [
        text("Rating before request"),
        h.strong([], [text(n(rep.rating(before)) <> "/100")]),
      ]),
      h.span([], [
        text("Final request"),
        h.strong([], [text(units(model.strategy.request))]),
      ]),
    ]),
    h.div([cls("service-status")], [
      h.span(
        [
          cls(
            "status-dot "
            <> case frame.outcome {
              rep.Defaulted -> "rogue"
              _ -> "moss"
            },
          ),
        ],
        [],
      ),
      text(rep.outcome_label(frame.outcome)),
      h.span([cls("mono muted")], [text(n(frame.successes) <> " fulfilled")]),
    ]),
  ])
}

fn strategy_row(name: String, value: String) {
  h.div([], [h.span([], [text(name)]), h.strong([], [text(value)])])
}

fn results(model: Model) {
  let final = rep.last(model.frames)
  let found = model.searched && final.loss > 0
  h.aside([cls("panel results"), attr("aria-live", "polite")], [
    h.div([cls("panel-title")], [label("03 / MEASURE THE DAMAGE")]),
    pill(
      case model.searched {
        False -> "AWAITING SEARCH"
        True ->
          case found {
            True -> "TRUST EXPLOIT FOUND"
            False -> "NO UNCOVERED LOSS"
          }
      },
      case found {
        True -> "orange"
        False -> "neutral"
      },
    ),
    h.h3([cls("outcome-title")], [
      text(case model.searched {
        False -> "Trust, before it is tested."
        True ->
          case found {
            True -> "Earn trust cheaply. Default big."
            False -> "The promise has a limit."
          }
      }),
    ]),
    h.p([cls("muted small")], [
      text(case model.searched {
        False ->
          "The baseline seller fulfills every approved request. Search for the damage a strategic default can cause."
        True ->
          case found {
            True ->
              "A good rating opens the gate. Locked collateral covers only part of the defaulted request."
            False ->
              "No candidate leaves an uncovered loss under these rules. Replay the request to see whether it was rejected or covered."
          }
      }),
    ]),
    h.div([cls("gain-number")], [
      text(n(final.loss)),
      h.span([], [text("credits lost")]),
    ]),
    h.div([cls("comparison")], [
      loss_bar("Honest", rep.last(model.baseline).loss, "base"),
      loss_bar(
        case model.searched {
          True -> "Worst found"
          False -> "Current"
        },
        final.loss,
        "best",
      ),
    ]),
    h.div([cls("strategy")], [
      label(case model.searched {
        True -> "STRATEGY UNDER TEST"
        False -> "BASELINE STRATEGY"
      }),
      strategy_row("Small deliveries", n(model.strategy.history)),
      strategy_row("Each delivery", units(model.strategy.small)),
      strategy_row("Final request", units(model.strategy.request)),
      strategy_row("Collateral seized", units(final.seized)),
    ]),
    h.button([cls("secondary"), event.on_click(Repair)], [
      text("Require collateral"),
      h.span([], [text("→")]),
    ]),
    h.p([cls("search-note")], [
      text("Rechecks all 48 strategies with the new rule."),
    ]),
  ])
}

fn loss_bar(title: String, value: Int, class: String) {
  h.div([cls("comparison-row")], [
    h.span([], [text(title)]),
    h.div([cls("bar-track")], [
      h.div(
        [cls("bar " <> class), a.style("width", n(value * 100 / 64) <> "%")],
        [],
      ),
    ]),
    h.strong([], [text(n(value))]),
  ])
}

fn timeline(model: Model) {
  let last = rep.last(model.frames).step
  h.section([cls("panel timeline reputation-timeline")], [
    h.div([cls("timeline-heading")], [
      h.div([], [
        label("THE REPLAY"),
        h.span([cls("muted small")], [
          text("Small deliveries first. The large request comes last."),
        ]),
      ]),
      h.div([cls("replay-actions")], [
        h.button([cls("text-button"), event.on_click(Export)], [
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
      [cls("timeline-track")],
      list.map(list.drop(model.frames, 1), fn(frame) {
        let final = frame.step == last
        h.button(
          [
            cls(
              "tick "
              <> case final {
                True -> "rogue"
                False -> "moss"
              }
              <> case frame.step == model.step {
                True -> " selected"
                False -> ""
              },
            ),
            event.on_click(Seek(frame.step)),
            attr(
              "aria-label",
              "Step "
                <> n(frame.step)
                <> ": "
                <> rep.outcome_label(frame.outcome)
                <> ", "
                <> units(frame.amount),
            ),
            attr("aria-pressed", case frame.step == model.step {
              True -> "true"
              False -> "false"
            }),
          ],
          [
            text(case final {
              True -> "Request " <> n(frame.amount)
              False -> "Deliver " <> n(frame.amount)
            }),
          ],
        )
      }),
    ),
    h.div([cls("playback")], [
      h.button(
        [
          cls("transport"),
          event.on_click(Seek(0)),
          a.disabled(model.step == 0),
          attr("aria-label", "Rewind to start"),
        ],
        [text("↤")],
      ),
      h.button(
        [
          cls("transport"),
          event.on_click(Seek(model.step - 1)),
          a.disabled(model.step == 0),
          attr("aria-label", "Previous step"),
        ],
        [text("←")],
      ),
      h.button(
        [
          cls("transport"),
          event.on_click(Seek(model.step + 1)),
          a.disabled(model.step == last),
          attr("aria-label", "Next step"),
        ],
        [text("→")],
      ),
      h.input([
        a.type_("range"),
        a.min("0"),
        a.max(n(last)),
        a.value(n(model.step)),
        event.on_input(Scrub),
        attr("aria-label", "Replay step"),
      ]),
      h.span([cls("mono")], [text(n(model.step) <> " / " <> n(last))]),
    ]),
  ])
}

pub fn receipt(model: Model) -> String {
  json.object([
    #("schema", json.string("loophole.reputation.v1")),
    #("version", json.string("0.2.0")),
    #("policy", json.string(rep.policy_key(model.rules.policy))),
    #("threshold", json.int(model.rules.threshold)),
    #("ceiling", json.int(model.rules.ceiling)),
    #("searched", json.bool(model.searched)),
    #(
      "strategies_tested",
      json.int(case model.searched {
        True -> 48
        False -> 0
      }),
    ),
    #(
      "strategy",
      json.object([
        #("history", json.int(model.strategy.history)),
        #("small", json.int(model.strategy.small)),
        #("request", json.int(model.strategy.request)),
      ]),
    ),
    #("baseline_loss", json.int(rep.last(model.baseline).loss)),
    #("loss", json.int(rep.last(model.frames).loss)),
    #("replay_fragment", json.string(share_url(model))),
    #(
      "frames",
      json.array(model.frames, fn(frame) {
        json.object([
          #("step", json.int(frame.step)),
          #("successes", json.int(frame.successes)),
          #("failures", json.int(frame.failures)),
          #("delivered", json.int(frame.delivered)),
          #("bond", json.int(frame.bond)),
          #("seized", json.int(frame.seized)),
          #("loss", json.int(frame.loss)),
          #("amount", json.int(frame.amount)),
          #("rating", json.int(rep.rating(frame))),
          #("outcome", json.string(rep.outcome_key(frame.outcome))),
        ])
      }),
    ),
  ])
  |> json.to_string
}
