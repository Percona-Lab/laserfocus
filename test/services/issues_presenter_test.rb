require "test_helper"

class IssuesPresenterTest < ActiveSupport::TestCase
  include GithubIssueFactory

  test "groups issues into the four columns, most stale first" do
    create_github_issue(number: 1, waiting_since: 1.day.ago)
    create_github_issue(number: 2, waiting_since: 5.days.ago)
    create_github_issue(number: 3, stage: "reporter", waiting_on: "reporter", waiting_since: 2.days.ago)
    presenter = IssuesPresenter.build
    assert_equal %w[new us reporter backlog], presenter.columns.map(&:id)
    assert_equal [ 2, 1 ], presenter.columns.first.cards.map(&:number)
  end

  test "each column has its own clock: slow on the reporter and the backlog" do
    team = create_github_issue(number: 1, waiting_since: 8.days.ago)
    reporter = create_github_issue(number: 2, stage: "reporter", waiting_on: "reporter", waiting_since: 8.days.ago)
    backlog = create_github_issue(number: 3, stage: "backlog", waiting_since: 40.days.ago, author_association: "MEMBER")
    cards = IssuesPresenter.build.cards.index_by(&:number)
    assert_equal :really, cards[team.number].staleness
    assert_equal :fresh, cards[reporter.number].staleness
    assert_equal :somewhat, cards[backlog.number].staleness
  end

  test "old issues need a decision, and the tab counts everything critical, the reporter's too" do
    create_github_issue(number: 1, waiting_since: 8.days.ago, opened_at: 100.days.ago)
    create_github_issue(number: 2, stage: "reporter", waiting_on: "reporter", waiting_since: 40.days.ago)
    create_github_issue(number: 3, stage: "reporter", waiting_on: "reporter", waiting_since: 2.days.ago)
    presenter = IssuesPresenter.build
    assert presenter.cards.find { |c| c.number == 1 }.decision?
    assert_equal :really, presenter.cards.find { |c| c.number == 2 }.staleness
    assert_equal 2, IssuesPresenter.critical_count
  end

  test "a snooze holds until the ball moves" do
    issue = create_github_issue(number: 1, waiting_since: 8.days.ago)
    StaleSnooze.create!(jira_key: issue.key, jira_status: issue.snooze_state, snoozed_until: 2.days.from_now, snoozed_by: "A")
    assert IssuesPresenter.build.cards.first.snoozed?

    issue.update!(stage: "us", waiting_since: 7.days.ago)
    refute IssuesPresenter.build.cards.first.snoozed?
  end

  test "Needs me is what is assigned to the viewer and waits on the team; Mine finds their login" do
    create_github_issue(number: 1, assignees: [ "alice-gh" ])
    create_github_issue(number: 2, assignees: [ "alice-gh" ], stage: "reporter", waiting_on: "reporter")
    presenter = IssuesPresenter.build(viewer: { name: "Alice", github: "alice-gh" })
    assert_equal [ true, false ], presenter.cards.sort_by(&:number).map { |c| presenter.needs_viewer?(c) }
    assert_equal "alice-gh", presenter.viewer_login
  end

  test "commenters and assignees show up under People" do
    create_github_issue(number: 1, author: "rita", assignees: [ "alice-gh" ],
                        comments: [ { "login" => "x9", "team" => false, "at" => 1.day.ago.iso8601 } ])
    presenter = IssuesPresenter.build
    assert_equal [ "alice-gh" ], presenter.team_logins
    assert_equal %w[rita x9], presenter.outside_logins.sort
    assert_equal({ wrote: 0, replied: 1, asked: 0 }, presenter.involvement("x9"))
    assert_equal({ wrote: 0, replied: 0, asked: 1 }, presenter.involvement("alice-gh"))
  end
end
