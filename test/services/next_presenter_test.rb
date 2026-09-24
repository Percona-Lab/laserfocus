require "test_helper"

class NextPresenterTest < ActiveSupport::TestCase
  fixtures :epics, :issues

  def idea(key, incubator: "Committed", deliveries: [], rank: "0|a")
    record = DiscoveryIdea.create!(jira_key: key, summary: "Idea #{key}", horizon: "next",
                                   incubator_status: incubator, rank: rank)
    deliveries.each { |d| record.idea_deliveries.create!(jira_key: d[:key], issue_type: d[:type]) }
    record
  end

  test "an idea with no delivery ticket scores nothing" do
    idea("PGR-1", deliveries: [])
    row = NextPresenter.build.rows.first
    assert_equal 0, row.steps
    assert_equal "No delivery ticket", row.blocker
    refute row.ready?
  end

  test "an idea delivered by a Story is not startable" do
    idea("PGR-2", deliveries: [ { key: "PG-2425", type: "Story" } ])
    row = NextPresenter.build.rows.first
    assert_equal 1, row.steps
    assert_equal "Delivered by a Story, not an epic", row.blocker
  end

  test "an idea pointing at an epic the board does not carry names it" do
    idea("PGR-6", deliveries: [ { key: "PG-1572", type: "Epic" } ])
    row = NextPresenter.build.rows.first
    assert_equal 1, row.steps
    assert_equal "PG-1572 is not on the board", row.blocker
  end

  test "a removed epic counts as not on the board" do
    Epic.create!(jira_key: "PG-60", name: "Gone", jira_status: "To Do", priority: 1,
                 removed_at: Time.current)
    idea("PGR-7", deliveries: [ { key: "PG-60", type: "Epic" } ])
    assert_equal "PG-60 is not on the board", NextPresenter.build.rows.first.blocker
  end

  test "unlinked_count counts the items with nothing in Jira" do
    idea("PGR-A", rank: "0|a", deliveries: [])
    idea("PGR-B", rank: "0|b", deliveries: [])
    idea("PGR-C", rank: "0|c", deliveries: [ { key: "PG-1", type: "Epic" } ])

    presenter = NextPresenter.build
    assert_equal 2, presenter.unlinked_count
    assert_equal 3, presenter.rows.size
  end

  test "an epic with no tickets stops at step two" do
    Epic.create!(jira_key: "PG-50", name: "Empty epic", jira_status: "To Do", priority: 1)
    idea("PGR-3", deliveries: [ { key: "PG-50", type: "Epic" } ])

    row = NextPresenter.build.rows.first
    assert_equal 2, row.steps
    assert_equal "Epic has no tickets yet", row.blocker
  end

  test "an unready incubator status stops at step three" do
    idea("PGR-4", incubator: "Prioritized", deliveries: [ { key: "PG-1", type: "Epic" } ])
    row = NextPresenter.build.rows.first
    assert_equal 3, row.steps
    assert_equal "Still Prioritized", row.blocker
  end

  test "a committed idea with a populated epic is ready" do
    idea("PGR-5", incubator: "Committed", deliveries: [ { key: "PG-1", type: "Epic" } ])
    row = NextPresenter.build.rows.first

    assert_equal NextPresenter::TOTAL_STEPS, row.steps
    assert_nil row.blocker
    assert row.ready?
    assert_equal 4, row.deliveries.first.ticket_count
  end

  test "rows follow the roadmap rank and count the ready ones" do
    idea("PGR-B", rank: "0|b", deliveries: [ { key: "PG-1", type: "Epic" } ])
    idea("PGR-A", rank: "0|a", deliveries: [])

    presenter = NextPresenter.build
    assert_equal %w[PGR-A PGR-B], presenter.rows.map { |r| r.idea.jira_key }
    assert_equal 1, presenter.ready_count
  end

  test "ideas in the Now horizon are not listed" do
    DiscoveryIdea.create!(jira_key: "PGR-9", summary: "Now item", horizon: "now")
    assert_empty NextPresenter.build.rows
  end

  test "the checklist points at the first missing step and waits on the rest" do
    idea("PGR-1", incubator: "Discovery", deliveries: [])
    states = NextPresenter.build.rows.first.checklist.map(&:state)
    assert_equal %i[current todo todo todo], states
  end

  test "the checklist judges each step on its own" do
    idea("PGR-2", incubator: "Committed", deliveries: [])
    row = NextPresenter.build.rows.first
    assert_equal %i[current todo todo done], row.checklist.map(&:state)
    assert_equal 1, row.steps_met
    assert_equal 0, row.steps
  end

  test "an epic that is not on the board asks for the Priority label" do
    idea("PGR-6", deliveries: [ { key: "PG-1572", type: "Epic" } ])
    step = NextPresenter.build.rows.first.checklist.second
    assert_equal :current, step.state
    assert_equal "PG-1572 is not on the board. Add the Priority label", step.detail
    assert_equal "PG-1572", step.jira_key
  end

  test "a ready idea has every step done" do
    idea("PGR-9", deliveries: [ { key: "PG-1", type: "Epic" } ])
    row = NextPresenter.build.rows.first
    assert row.ready?
    assert_equal [ :done ] * 4, row.checklist.map(&:state)
    assert_match(/ticket/, row.checklist.third.detail)
  end
end
