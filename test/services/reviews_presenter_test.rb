require "test_helper"

class ReviewsPresenterTest < ActiveSupport::TestCase
  include ReviewPrFactory

  def card(pr, viewer: nil) = ReviewsPresenter.build(viewer: viewer).cards.find { |c| c.pr.id == pr.id }

  test "waiting on reviewers: stale after 3 days, critical after 7" do
    freeze_time do
      assert_equal :fresh, card(create_review_pr(number: 1, waiting_since: 2.days.ago)).staleness
      assert_equal :somewhat, card(create_review_pr(number: 2, waiting_since: 3.days.ago)).staleness
      assert_equal :really, card(create_review_pr(number: 3, waiting_since: 7.days.ago)).staleness
    end
  end

  test "thresholds fire an hour early, like tickets" do
    freeze_time do
      assert_equal :somewhat, card(create_review_pr(waiting_since: 3.days.ago + 30.minutes)).staleness
    end
  end

  test "waiting on the author uses the slower clock" do
    freeze_time do
      pr = create_review_pr(stage: "changes", waiting_on: "author", waiting_since: 8.days.ago)
      assert_equal :somewhat, card(pr).staleness
    end
  end

  test "open 30 days needs a decision, whatever the waiting clock says" do
    freeze_time do
      pr = create_review_pr(stage: "discuss", waiting_on: "author", waiting_since: 1.day.ago, opened_at: 31.days.ago)
      assert card(pr).decision?
      assert_not card(create_review_pr(number: 2, opened_at: 20.days.ago)).decision?
    end
  end

  test "a snooze quiets a stale PR and its decision flag while the ball stays put" do
    freeze_time do
      pr = create_review_pr(waiting_since: 40.days.ago)
      StaleSnooze.create!(jira_key: pr.key, jira_status: pr.snooze_state, snoozed_until: 3.days.from_now, snoozed_by: "Alice")
      c = card(pr)
      assert_equal :snoozed, c.staleness
      assert_not c.decision?

      pr.update!(waiting_since: 39.days.ago)
      assert_equal :really, card(pr).staleness
    end
  end

  test "columns follow the stages, most stale first" do
    old = create_review_pr(number: 1, waiting_since: 9.days.ago)
    young = create_review_pr(number: 2, waiting_since: 1.day.ago)
    create_review_pr(number: 3, stage: "approved", waiting_on: "merge")

    columns = ReviewsPresenter.build.columns
    assert_equal %w[needs discuss changes approved], columns.map(&:id)
    assert_equal [ old.id, young.id ], columns.first.cards.map { |c| c.pr.id }
    assert_equal 1, columns.last.cards.size
  end

  test "needs me: requested, or reviewed and the author pushed since" do
    requested = create_review_pr(number: 1, requested_reviewers: [ "Alice-GH" ])
    pushed = create_review_pr(number: 2, stage: "discuss", waiting_on: "reviewers",
                              reviews: [ { "login" => "alice-gh", "state" => "COMMENTED" } ])
    answered = create_review_pr(number: 3, stage: "discuss", waiting_on: "author",
                                reviews: [ { "login" => "alice-gh", "state" => "COMMENTED" } ])
    presenter = ReviewsPresenter.build(viewer: { github: "alice-gh" })
    by_id = presenter.cards.index_by { |c| c.pr.id }

    assert presenter.needs_viewer?(by_id[requested.id])
    assert presenter.needs_viewer?(by_id[pushed.id])
    assert_not presenter.needs_viewer?(by_id[answered.id])
  end

  test "counts critical PRs for the tab badge, not snoozed ones" do
    freeze_time do
      create_review_pr(number: 1, waiting_since: 8.days.ago)
      create_review_pr(number: 2, waiting_since: 4.days.ago)
      snoozed = create_review_pr(number: 3, waiting_since: 8.days.ago)
      StaleSnooze.create!(jira_key: snoozed.key, jira_status: snoozed.snooze_state, snoozed_until: 1.day.from_now, snoozed_by: "A")
      assert_equal 1, ReviewsPresenter.critical_count
    end
  end

  test "lists every configured repo with its count" do
    create_review_pr(repo: "acme/server", number: 1)
    assert_equal [ [ "acme/server", 1 ], [ "acme/docs", 0 ] ], ReviewsPresenter.build.repos
  end

  test "an excluded repo's PRs are left out, its row keeps the count it would show" do
    freeze_time do
      create_review_pr(repo: "acme/server", number: 1, waiting_since: 8.days.ago)
      create_review_pr(repo: "acme/docs", number: 2, waiting_since: 8.days.ago)
      presenter = ReviewsPresenter.build(excluded: Set["Acme/Docs"])

      assert_equal [ "acme/server" ], presenter.cards.map(&:repo)
      assert_equal [ [ "acme/server", 1 ], [ "acme/docs", 1 ] ], presenter.repos
      assert presenter.excluded?("acme/docs")
      assert_not presenter.excluded?("acme/server")
      assert_equal 1, ReviewsPresenter.critical_count(excluded: Set["acme/docs"])
      assert_equal 2, ReviewsPresenter.critical_count
    end
  end

  test "the viewer is found by name when they have no github override" do
    create_review_pr(number: 1, author: "KW", people_names: { "KW" => "Kai Wagner" })
    assert_equal "kw", ReviewsPresenter.build(viewer: { name: "Kai Wagner" }).viewer_login
  end

  test "the viewer is found when they only reviewed, and by their github override" do
    create_review_pr(number: 1, author: "zp", reviews: [ { "login" => "ImTheKai", "state" => "COMMENTED" } ])
    assert_equal "imthekai", ReviewsPresenter.build(viewer: { name: "Someone", github: "imthekai" }).viewer_login
    assert_nil ReviewsPresenter.build(viewer: { name: "Someone Else" }).viewer_login
  end

  test "splits people into the team and everyone else, with what they did" do
    create_review_pr(number: 1, author: "zp", people_names: { "zp" => "Zsolt Parragi", "x9" => "Ext Person" },
                     reviews: [ { "login" => "x9", "state" => "COMMENTED" } ])
    users = [ OpenStruct.new(display_name: "Zsolt Parragi"), OpenStruct.new(display_name: "Nobody Here") ]
    prs = ReviewPullRequest.all.to_a
    presenter = ReviewsPresenter.new(prs: prs, people: ReviewPeople.from_prs(prs, users: users))

    assert_equal [ "zp" ], presenter.team_logins
    assert_equal [ "x9" ], presenter.outside_logins
    assert_equal [ "Nobody Here" ], presenter.unmatched_members.map(&:display_name)
    assert_equal({ wrote: 0, replied: 1, asked: 0 }, presenter.involvement("x9"))
    assert_equal 0, presenter.no_reply_count
  end
end
