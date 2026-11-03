import gleam/int
import gleam/json
import gleam/list
import gleam/string
import loophole/collusion as ring
import loophole/engine
import lustre/attribute as a
import lustre/element.{type Element, text}
import lustre/element/html as h
import lustre/event

pub type Model {
  Model(
    rules: ring.Rules,
    strategy: ring.Strategy,
    frames: List(ring.Frame),
    step: Int,
    searched: Bool,
    feasible: Int,
  )
}

pub type Msg {
  Search
  Repair
  Bypass
  Policy(String)
  Budget(String)
  Threshold(String)
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

fn fresh(rules: ring.Rules) {
  Model(
    rules,
    ring.default_strategy(),
    ring.run(rules, ring.default_strategy(), False),
    1,
    False,
    0,
  )
}

fn searched(rules: ring.Rules) {
  let found = ring.search(rules)
  Model(
    rules,
    found.strategy,
    found.frames,
    ring.last(found.frames).step,
    True,
    found.feasible,
  )
}

pub fn init(fragment: String) -> Model {
  case string.split(fragment, ":") {
    ["ring1", policy, budget, threshold, mode, step] -> {
      let rules =
        ring.Rules(
          case policy {
            "unique" -> ring.OnePerReviewer
            _ -> ring.EveryReview
          },
          parsed(budget, 20, 3, 40),
          parsed(threshold, 80, 50, 99),
        )
      let model = case mode {
        "searched" -> searched(rules)
        _ -> fresh(rules)
      }
      Model(
        ..model,
        step: parsed(
          step,
          ring.last(model.frames).step,
          0,
          ring.last(model.frames).step,
        ),
      )
    }
    _ -> fresh(ring.default_rules())
  }
}

pub fn update(model: Model, message: Msg) -> Model {
  case message {
    Search -> searched(model.rules)
    Repair -> searched(ring.Rules(..model.rules, policy: ring.OnePerReviewer))
    Bypass -> searched(ring.Rules(ring.OnePerReviewer, 24, 80))
    Policy(value) ->
      fresh(
        ring.Rules(..model.rules, policy: case value {
          "unique" -> ring.OnePerReviewer
          _ -> ring.EveryReview
        }),
      )
    Budget(value) ->
      fresh(ring.Rules(..model.rules, budget: parsed(value, 20, 3, 40)))
    Threshold(value) ->
      fresh(ring.Rules(..model.rules, threshold: parsed(value, 80, 50, 99)))
    Seek(step) ->
      Model(..model, step: int.clamp(step, 0, ring.last(model.frames).step))
    Scrub(value) ->
      Model(..model, step: parsed(value, 0, 0, ring.last(model.frames).step))
    Reset -> fresh(ring.default_rules())
    Export -> model
  }
}

pub fn share_url(model: Model) -> String {
  "#ring1:"
  <> ring.policy_key(model.rules.policy)
  <> ":"
  <> n(model.rules.budget)
  <> ":"
  <> n(model.rules.threshold)
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

fn event_label(frame: ring.Frame) {
  case frame.event {
    ring.Start -> "Four genuine reviews establish the baseline"
    ring.AccountOpened ->
      "Coordinated account R" <> n(frame.reviewer + 1) <> " opened · cost 2"
    ring.ReviewPosted ->
      "R" <> n(frame.reviewer + 1) <> " posted a five-star review · cost 1"
    ring.Decision -> "Promotion decision evaluated"
    ring.BudgetRejected -> "Strategy rejected before spending"
  }
}

pub fn view(model: Model) -> Element(Msg) {
  h.div([cls("collusion-experiment")], [
    h.div([cls("lab-heading"), a.id("laboratory")], [
      h.div([], [label("EXPERIMENT 03"), h.h2([], [text("The review ring")])]),
      pill("Four real opinions. A manufactured crowd.", "neutral"),
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
          text("More reviews."),
          h.br([]),
          h.span([cls("muted")], [text("Not necessarily more people.")]),
        ]),
        h.p([], [
          text(case model.rules.policy {
            ring.EveryReview ->
              "Four genuine reviewers give two stars each. A coordinated group adds only five-star reviews. Counting every review lets a small group repeat its opinion until the seller crosses the promotion threshold. The real feedback never improves."
            ring.OnePerReviewer ->
              "Capping each reviewer removes the advantage of repeating an opinion. The search adapts by buying more accounts. At budget 20 the best candidate reaches 76, below an 80-point gate; at budget 24, eight accounts reach 80. An account is not proof of an independent person."
          }),
        ]),
      ]),
      h.details([cls("methodology")], [
        h.summary([], [
          text("What this review model assumes"),
          h.span([], [text("+")]),
        ]),
        h.div([cls("method-body")], [
          h.p([], [
            text(
              "Four distinct genuine reviewers each give two stars (40/100). Coordinated reviewers always give five stars (100/100). An account costs 2 budget units and each submitted review costs 1. All feedback is synthetic.",
            ),
          ]),
          h.p([], [
            text(
              "The 24 candidate strategies use 1, 2, 3, 4, 6 or 8 coordinated accounts, with 1, 2, 4 or 8 reviews each. Unaffordable plans are rejected without spending. Search maximizes displayed rating, then minimizes cost on ties.",
            ),
          ]),
          h.p([], [
            text(
              "Every-review policy averages all reviews. One-vote policy counts only the first review from each reviewer. Repeats still cost budget but add no weight. The baseline has only the four genuine reviews and spends nothing.",
            ),
          ]),
          h.p([], [
            text(
              "The decision is evaluated after all submitted reviews. Passing the threshold is a promotion, not proof of quality. Reviewer labels are known to this simulator; the policy does not detect collusion or identify real people.",
            ),
          ]),
          h.p([], [
            text(
              "No real accounts, review posting, networks, money, identity verification, or abuse evasion. The fixed costs and review set are model assumptions. This experiment is not a production moderation benchmark.",
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
      label("01 / WEIGH THE FEEDBACK"),
      h.span([cls("tiny-icon")], [text("≡")]),
    ]),
    h.h3([], [text("How many voices are in the room?")]),
    h.p([cls("muted small")], [
      text(
        "Keep genuine feedback fixed. Let the search spend a budget on coordinated accounts and repeated praise.",
      ),
    ]),
    h.label([a.for("review-policy")], [text("Review weighting")]),
    h.select([a.id("review-policy"), event.on_change(Policy)], [
      h.option(
        [a.value("all"), a.selected(model.rules.policy == ring.EveryReview)],
        "Every review counts",
      ),
      h.option(
        [
          a.value("unique"),
          a.selected(model.rules.policy == ring.OnePerReviewer),
        ],
        "One vote per reviewer",
      ),
    ]),
    h.p([cls("field-help")], [
      text(case model.rules.policy {
        ring.EveryReview ->
          "Repeated reviews from one account keep adding weight."
        ring.OnePerReviewer ->
          "A reviewer gets one vote, even after repeated posts."
      }),
    ]),
    h.div([cls("range-heading")], [
      h.label([a.for("ring-budget")], [text("Coordination budget")]),
      h.output([a.for("ring-budget")], [text(n(model.rules.budget) <> " units")]),
    ]),
    h.input([
      a.id("ring-budget"),
      a.type_("range"),
      a.min("3"),
      a.max("40"),
      a.value(n(model.rules.budget)),
      event.on_input(Budget),
    ]),
    h.div([cls("range-ends")], [text("3"), h.span([], [text("40")])]),
    h.div([cls("range-heading")], [
      h.label([a.for("promotion-threshold")], [text("Promotion threshold")]),
      h.output([a.for("promotion-threshold")], [
        text(n(model.rules.threshold) <> "/100"),
      ]),
    ]),
    h.input([
      a.id("promotion-threshold"),
      a.type_("range"),
      a.min("50"),
      a.max("99"),
      a.value(n(model.rules.threshold)),
      event.on_input(Threshold),
    ]),
    h.div([cls("range-ends")], [text("50"), h.span([], [text("99")])]),
    h.button([cls("primary"), event.on_click(Search)], [
      text("Find a review exploit"),
      h.span([], [text("↗")]),
    ]),
    h.p([cls("search-note")], [
      text("24 strategies. Account cost 2. Review cost 1."),
    ]),
    h.button([cls("text-button"), event.on_click(Reset)], [
      text("↺ Reset review experiment"),
    ]),
  ])
}

fn arena(model: Model) {
  let frame = ring.frame_at(model.frames, model.step)
  let score = ring.rating(frame, model.rules.policy)
  h.section([cls("panel arena review-arena")], [
    h.div([cls("panel-title")], [
      label("02 / INSPECT THE CROWD"),
      pill(
        case model.searched {
          True -> "SEARCH COMPLETE"
          False -> "GENUINE BASELINE"
        },
        "lavender",
      ),
    ]),
    h.div([cls("arena-caption")], [
      text("The feedback is unchanged. Its weight is not."),
      h.span([cls("mono")], [text("step " <> n(model.step))]),
    ]),
    h.div(
      [
        cls("review-score"),
        attr("role", "img"),
        attr(
          "aria-label",
          "Review score at step "
            <> n(model.step)
            <> ": rating "
            <> n(score)
            <> ", coordinated reviews "
            <> n(ring.posted(frame))
            <> ", counted "
            <> n(ring.counted(frame, model.rules.policy))
            <> ", spent "
            <> n(frame.spent),
        ),
      ],
      [
        h.div([], [
          label("DISPLAYED RATING"),
          h.strong([], [text(n(score)), h.span([], [text("/100")])]),
        ]),
        h.div([cls("score-baseline")], [
          label("GENUINE FEEDBACK"),
          h.strong([], [text("40"), h.span([], [text("/100")])]),
        ]),
      ],
    ),
    h.div([cls("genuine-row")], [
      h.span([cls("reviewer-icon genuine-icon")], [text("4")]),
      h.div([], [
        h.strong([], [text("Four genuine reviewers")]),
        h.span([], [text("2 stars each · one review per person")]),
      ]),
      h.span(
        [cls("stars genuine-stars"), attr("aria-label", "2 out of 5 stars")],
        [text("★★☆☆☆")],
      ),
    ]),
    h.div(
      [cls("review-grid"), attr("aria-label", "Coordinated reviewers")],
      case frame.reviews {
        [] -> [
          h.p([cls("empty-crowd")], [
            text(
              "No coordinated accounts yet. Step through the replay to watch the crowd form.",
            ),
          ]),
        ]
        _ ->
          list.index_map(frame.reviews, fn(reviews, index) {
            h.div(
              [
                cls(
                  "reviewer-card"
                  <> case index == frame.reviewer {
                    True -> " active-reviewer"
                    False -> ""
                  },
                ),
              ],
              [
                h.div([cls("reviewer-card-heading")], [
                  h.span([cls("reviewer-icon")], [text("R" <> n(index + 1))]),
                  h.span([], [text(n(reviews) <> " posted")]),
                  h.span(
                    [
                      cls("stars"),
                      attr("aria-label", "Coordinated five-star reviews"),
                    ],
                    [
                      text(case reviews > 0 {
                        True -> "★★★★★"
                        False -> "—"
                      }),
                    ],
                  ),
                ]),
                h.div(
                  [
                    cls("vote-dots"),
                    attr(
                      "aria-label",
                      "R" <> n(index + 1) <> ": " <> n(reviews) <> " reviews",
                    ),
                  ],
                  list.map(engine.range(1, reviews), fn(i) {
                    h.span(
                      [
                        cls(
                          case
                            model.rules.policy == ring.OnePerReviewer && i > 1
                          {
                            True -> "vote-dot ignored-vote"
                            False -> "vote-dot"
                          },
                        ),
                        a.title(
                          case
                            model.rules.policy == ring.OnePerReviewer && i > 1
                          {
                            True -> "Repeated vote: ignored"
                            False -> "Vote counted"
                          },
                        ),
                      ],
                      [],
                    )
                  }),
                ),
              ],
            )
          })
      },
    ),
    history_chart(model),
    h.div([cls("review-ledger")], [
      h.span([], [
        text("Submitted "),
        h.strong([], [text(n(ring.posted(frame)))]),
      ]),
      h.span([], [
        text("Counted "),
        h.strong([], [text(n(ring.counted(frame, model.rules.policy)))]),
      ]),
      h.span([], [
        text("Spent "),
        h.strong([], [text(n(frame.spent) <> "/" <> n(model.rules.budget))]),
      ]),
    ]),
    h.div([cls("service-status")], [
      h.span([cls("status-dot rogue")], []),
      text(event_label(frame)),
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

fn chart_points(model: Model, frames: List(ring.Frame)) {
  list.map(frames, fn(frame) {
    n(15 + frame.step * 470 / ring.last(model.frames).step)
    <> ","
    <> n(110 - ring.rating(frame, model.rules.policy))
  })
  |> string.join(" ")
}

fn history_chart(model: Model) {
  h.div([cls("review-history")], [
    label("RATING HISTORY"),
    svg(
      "svg",
      [
        attr("viewBox", "0 0 500 100"),
        attr("role", "img"),
        attr(
          "aria-label",
          "Rating history with promotion threshold " <> n(model.rules.threshold),
        ),
      ],
      [
        svg(
          "line",
          [
            attr("x1", "15"),
            attr("x2", "485"),
            attr("y1", n(110 - model.rules.threshold)),
            attr("y2", n(110 - model.rules.threshold)),
            cls("threshold-line"),
          ],
          [],
        ),
        svg(
          "polyline",
          [
            attr("points", chart_points(model, model.frames)),
            cls("trust-line future"),
          ],
          [],
        ),
        svg(
          "polyline",
          [
            attr(
              "points",
              chart_points(model, list.take(model.frames, model.step + 1)),
            ),
            cls("trust-line"),
          ],
          [],
        ),
        svg(
          "circle",
          [
            attr("cx", n(15 + model.step * 470 / ring.last(model.frames).step)),
            attr(
              "cy",
              n(
                110
                - ring.rating(
                  ring.frame_at(model.frames, model.step),
                  model.rules.policy,
                ),
              ),
            ),
            attr("r", "4"),
            cls("trust-point default-point"),
          ],
          [],
        ),
      ],
    ),
    h.span([cls("chart-caption")], [
      text("Dashed line: promotion at " <> n(model.rules.threshold)),
    ]),
  ])
}

fn row(title: String, value: String) {
  h.div([], [h.span([], [text(title)]), h.strong([], [text(value)])])
}

fn results(model: Model) {
  let final = ring.last(model.frames)
  let score = ring.rating(final, model.rules.policy)
  let passes = ring.promoted(final, model.rules)
  h.aside([cls("panel results"), attr("aria-live", "polite")], [
    h.div([cls("panel-title")], [label("03 / CHECK THE CONSEQUENCE")]),
    pill(
      case model.searched {
        False -> "AWAITING SEARCH"
        True ->
          case passes {
            True -> "PROMOTION MANUFACTURED"
            False -> "PROMOTION BLOCKED"
          }
      },
      case model.searched && passes {
        True -> "orange"
        False -> "neutral"
      },
    ),
    h.h3([cls("outcome-title")], [
      text(case model.searched {
        False -> "A crowd, before the chorus."
        True ->
          case passes {
            True -> "The praise is coordinated."
            False -> "Blocked. Still inflated."
          }
      }),
    ]),
    h.p([cls("muted small")], [
      text(case model.searched {
        False ->
          "Four genuine opinions set the baseline. Search for the biggest rating boost the budget can buy."
        True ->
          case passes {
            True ->
              "Coordinated reviews cross the gate without changing a single genuine opinion."
            False ->
              "The best affordable candidate stays below the gate. Its votes still inflate the rating."
          }
      }),
    ]),
    h.div([cls("gain-number")], [
      text("+" <> n(score - 40)),
      h.span([], [text("rating points")]),
    ]),
    h.div([cls("review-outcome")], [
      row("Genuine rating", "40/100"),
      row(
        case model.searched {
          True -> "Highest found"
          False -> "Current rating"
        },
        n(score) <> "/100",
      ),
      row("Promotion gate", n(model.rules.threshold) <> "/100"),
    ]),
    h.div([cls("strategy")], [
      label(case model.searched {
        True -> "STRATEGY UNDER TEST"
        False -> "COORDINATED STRATEGY: NONE"
      }),
      row("Extra accounts", case model.searched {
        True -> n(model.strategy.accounts)
        False -> "0"
      }),
      row("Reviews per account", case model.searched {
        True -> n(model.strategy.repeats)
        False -> "0"
      }),
      row("Total cost", n(final.spent) <> " units"),
      row("Affordable candidates", case model.searched {
        True -> n(model.feasible) <> "/24"
        False -> "Not searched"
      }),
    ]),
    h.button([cls("secondary"), event.on_click(Repair)], [
      text("Cap each reviewer"),
      h.span([], [text("→")]),
    ]),
    h.button([cls("text-button bypass-button"), event.on_click(Bypass)], [
      text("Test the limit: budget 24 ↗"),
    ]),
    h.p([cls("search-note")], [
      text("Limit test sets one vote, budget 24, threshold 80."),
    ]),
  ])
}

fn timeline(model: Model) {
  let last = ring.last(model.frames).step
  h.section([cls("panel timeline")], [
    h.div([cls("timeline-heading")], [
      h.div([], [
        label("THE REPLAY"),
        h.span([cls("muted small")], [
          text("Open accounts. Post reviews. Evaluate the gate."),
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
        h.button(
          [
            cls(
              "tick "
              <> case frame.event {
                ring.AccountOpened -> "nova"
                ring.Decision -> "atlas"
                _ -> "rogue"
              }
              <> case frame.step == model.step {
                True -> " selected"
                False -> ""
              },
            ),
            event.on_click(Seek(frame.step)),
            attr(
              "aria-label",
              "Step " <> n(frame.step) <> ": " <> event_label(frame),
            ),
            attr("aria-pressed", case frame.step == model.step {
              True -> "true"
              False -> "false"
            }),
            a.title(event_label(frame)),
          ],
          [
            text(case frame.event {
              ring.AccountOpened -> "A" <> n(frame.reviewer + 1)
              ring.ReviewPosted -> "+"
              ring.Decision -> "✓"
              _ -> "×"
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
  let final = ring.last(model.frames)
  json.object([
    #("schema", json.string("loophole.collusion.v1")),
    #("version", json.string("0.3.0")),
    #("policy", json.string(ring.policy_key(model.rules.policy))),
    #("budget", json.int(model.rules.budget)),
    #("threshold", json.int(model.rules.threshold)),
    #("searched", json.bool(model.searched)),
    #(
      "strategies_tested",
      json.int(case model.searched {
        True -> 24
        False -> 0
      }),
    ),
    #("feasible", json.int(model.feasible)),
    #(
      "strategy",
      json.object([
        #("accounts", json.int(model.strategy.accounts)),
        #("repeats", json.int(model.strategy.repeats)),
      ]),
    ),
    #("baseline_rating", json.int(40)),
    #("rating", json.int(ring.rating(final, model.rules.policy))),
    #("promoted", json.bool(ring.promoted(final, model.rules))),
    #("replay_fragment", json.string(share_url(model))),
    #(
      "frames",
      json.array(model.frames, fn(frame) {
        json.object([
          #("step", json.int(frame.step)),
          #("reviews", json.array(frame.reviews, json.int)),
          #("spent", json.int(frame.spent)),
          #("event", json.string(ring.event_key(frame.event))),
          #("reviewer", json.int(frame.reviewer)),
          #("counted", json.int(ring.counted(frame, model.rules.policy))),
          #("rating", json.int(ring.rating(frame, model.rules.policy))),
          #("promoted", json.bool(ring.promoted(frame, model.rules))),
        ])
      }),
    ),
  ])
  |> json.to_string
}
