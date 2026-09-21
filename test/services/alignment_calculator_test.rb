require "test_helper"

class AlignmentCalculatorTest < ActiveSupport::TestCase
  Epicish = Struct.new(:jira_key, :name, :in_progress, keyword_init: true) do
    def in_progress? = !!in_progress
  end

  def column(key, new: 0, middle: 0, done: 0, lane: :focus, idea: nil, in_progress: false)
    BoardPresenter::Column.new(
      Epicish.new(jira_key: key, name: "Epic #{key}", in_progress: in_progress),
      Array.new(new) { :issue },
      middle.zero? ? {} : { "in_progress" => Array.new(middle) { :issue } },
      Array.new(done) { :issue },
      false, lane, idea
    )
  end

  def idea(key, delivery_keys, summary: "An idea")
    record = DiscoveryIdea.create!(jira_key: key, summary: summary, horizon: "now")
    delivery_keys.each { |k| record.idea_deliveries.create!(jira_key: k, issue_type: "Epic") }
    record
  end

  test "reports nothing when there is no roadmap configured" do
    calc = AlignmentCalculator.new(columns: [ column("PG-1", middle: 1) ], now_ideas: [])
    refute calc.configured?
  end

  test "counts how many Now items reached the board" do
    on_board = idea("PGR-1", %w[PG-1])
    off_board = idea("PGR-2", %w[PG-9])

    calc = AlignmentCalculator.new(columns: [ column("PG-1", middle: 1, idea: on_board) ],
                                   now_ideas: [ on_board, off_board ])

    assert_equal 2, calc.now_total
    assert_equal 1, calc.now_on_board
    assert_equal 1, calc.needs_attention
  end

  test "flags a Now item with no delivery ticket" do
    calc = AlignmentCalculator.new(columns: [], now_ideas: [ idea("PGR-1", []) ])
    finding = calc.findings.find { |f| f.kind == :no_delivery }

    assert_equal "PGR-1", finding.key
    assert_equal :high, finding.severity
  end

  test "a Now item with no delivery counts as needing attention" do
    bare = idea("PGR-1", [])
    calc = AlignmentCalculator.new(columns: [ column("PG-1", middle: 1) ], now_ideas: [ bare ])

    assert_equal 1, calc.now_total
    assert_equal 0, calc.now_on_board
    assert_equal 1, calc.needs_attention
    refute calc.aligned?
  end

  test "flags a Now item whose delivery ticket is not a column" do
    calc = AlignmentCalculator.new(columns: [ column("PG-1", middle: 1) ],
                                   now_ideas: [ idea("PGR-2", %w[PG-2425]) ])
    finding = calc.findings.find { |f| f.kind == :off_board }

    assert_equal "PGR-2", finding.key
    assert_includes finding.detail, "PG-2425"
  end

  test "flags a Now item on the board with nothing in flight" do
    committed = idea("PGR-3", %w[PG-3])
    calc = AlignmentCalculator.new(columns: [ column("PG-3", new: 10, idea: committed) ],
                                   now_ideas: [ committed ])
    finding = calc.findings.find { |f| f.kind == :not_started }

    assert_equal "PG-3", finding.key
    assert_includes finding.detail, "10 waiting"
  end

  test "flags a focus column with no roadmap item behind it" do
    backed = idea("PGR-1", %w[PG-1])
    calc = AlignmentCalculator.new(
      columns: [ column("PG-1", middle: 1, idea: backed), column("PG-2", middle: 2) ],
      now_ideas: [ backed ]
    )
    finding = calc.findings.find { |f| f.kind == :unbacked }

    assert_equal "PG-2", finding.key
    assert_equal :low, finding.severity
  end

  test "does not flag an ongoing column for missing a roadmap item" do
    backed = idea("PGR-1", %w[PG-1])
    calc = AlignmentCalculator.new(
      columns: [ column("PG-1", middle: 1, idea: backed), column("PG-2", middle: 2, lane: :ongoing) ],
      now_ideas: [ backed ]
    )
    assert_empty calc.findings.select { |f| f.kind == :unbacked }
  end

  test "flags an epic marked In Progress with nothing in flight" do
    backed = idea("PGR-1", %w[PG-1])
    calc = AlignmentCalculator.new(
      columns: [ column("PG-1", middle: 1, idea: backed),
                 column("PG-5", new: 5, in_progress: true, idea: backed) ],
      now_ideas: [ backed ]
    )
    finding = calc.findings.find { |f| f.kind == :status_drift }

    assert_equal "PG-5", finding.key
    assert_equal :medium, finding.severity
    assert_includes finding.detail, "5 waiting"
  end

  # The case that made the old wording wrong: the epic has a history of finished
  # work, so "nothing has started" was a lie. The note has to say so.
  test "an idle epic with finished work reports what it already did" do
    backed = idea("PGR-1", %w[PG-1])
    calc = AlignmentCalculator.new(
      columns: [ column("PG-1", new: 2, done: 7, in_progress: true, idea: backed) ],
      now_ideas: [ backed ]
    )
    finding = calc.findings.find { |f| f.kind == :status_drift }

    assert_includes finding.detail, "7 done, 2 waiting"
    refute_includes finding.detail, "have started"
  end

  test "findings come back worst first" do
    calc = AlignmentCalculator.new(
      columns: [ column("PG-2", middle: 2) ],
      now_ideas: [ idea("PGR-1", []) ]
    )
    assert_equal [ :high, :low ], calc.findings.map(&:severity)
  end
end
