require "application_system_test_case"

class ReviewsSystemTest < ApplicationSystemTestCase
  include ReviewPrFactory

  SERVER = ".kb-pr-card[data-snooze-key='acme/server#1']".freeze

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice Adams" }
    )
    StaleSnooze.delete_all
    create_review_pr(repo: "acme/server", number: 1, waiting_since: 9.days.ago)
    create_review_pr(repo: "acme/docs", number: 2, waiting_since: 9.days.ago, author: "outsider",
                     author_association: "FIRST_TIME_CONTRIBUTOR", requested_reviewers: [ "alice-gh" ],
                     reviews: [ { "login" => "bobby", "state" => "COMMENTED" } ],
                     people_names: { "bobby" => "Bob" })
    visit "/auth/google_oauth2/callback"
    visit "/reviews"
    assert_selector ".kb-pr-card", count: 2
  end

  test "the repo filter hides the other repos' PRs and updates the count" do
    find("[data-reviews-target='repoBtn']").click
    find(".kb-filter-row[data-repo='acme/docs']").click

    assert_selector ".kb-pr-card", count: 1
    assert_selector "#kb-reviews-needs .kb-col-count", text: "1/2"
    assert_selector "[data-reviews-target='repoBadge']", text: "1"

    click_button "✕ Clear selection"
    assert_selector ".kb-pr-card", count: 2
  end

  test "right-clicking a repo excludes it from my view, and again includes it" do
    RepoExclusion.delete_all
    find("[data-reviews-target='repoBtn']").click
    find(".kb-filter-row[data-repo='acme/docs']").right_click
    within(".kb-repo-ctx") { click_button "Exclude from my view" }

    assert_selector ".kb-pr-card", count: 1
    assert_no_selector ".kb-pr-card[data-repo='acme/docs']"
    # The dropdown stays open, the row has moved under Excluded at the bottom.
    assert_selector ".kb-repo-menu .kb-filter-row[data-repo='acme/docs'][data-excluded='1']"
    assert_selector ".kb-repo-menu .kb-filter-section-label", text: "EXCLUDED"
    assert_equal %w[acme/server acme/docs], all(".kb-repo-menu .kb-filter-row").map { |row| row["data-repo"] }
    assert_equal Set["acme/docs"], RepoExclusion.repos_for("alice@example.com")

    # A left click on an excluded repo does not tick it.
    find(".kb-filter-row[data-repo='acme/docs']").click
    assert_selector ".kb-pr-card", count: 1

    find(".kb-filter-row[data-repo='acme/docs']").right_click
    within(".kb-repo-ctx") { click_button "Include in my view again" }
    assert_selector ".kb-pr-card", count: 2
    assert_selector ".kb-filter-row[data-repo='acme/docs'][data-excluded='0']"
    assert_empty RepoExclusion.repos_for("alice@example.com")
  end

  test "the community toggle keeps only PRs from outside the org" do
    find(".kb-community-btn").click
    assert_selector ".kb-pr-card", count: 1
    assert_selector ".kb-pr-card .kb-pr-chip-community"
  end

  test "right-clicking a stale PR snoozes it" do
    find(SERVER).right_click
    within "#kb-snooze" do
      assert_text "acme/server#1 has been in Needs review for"
      assert_text "until the PR gets a new push or review"
      click_button "Snooze #{LASER_FOCUS_CONFIG.board.snooze_days} days"
    end

    assert_selector "#{SERVER}[data-staleness='snoozed']"
    assert StaleSnooze.exists?(jira_key: "acme/server#1")
  end

  test "the People filter matches by role, and No reply yet keeps unanswered PRs" do
    find("[data-reviews-target='peopleBtn']").click
    within ".kb-review-people" do
      find(".kb-people-row[data-login='bobby']").click
    end
    assert_selector ".kb-pr-card", count: 1
    assert_selector ".kb-pr-card[data-snooze-key='acme/docs#2'] .kb-avatar-hit[data-login='bobby']"

    within(".kb-review-people") { click_button "Wrote it" }
    assert_selector ".kb-pr-card", count: 0

    within(".kb-review-people") { click_button "✕ Clear selection" }
    within(".kb-review-people") { find("[data-reviews-target='noReplyRow']").click }
    assert_selector ".kb-pr-card", count: 1
    assert_selector ".kb-pr-card[data-snooze-key='acme/server#1']"
    assert_selector "[data-reviews-target='peopleLabel']", text: "No reply"
  end

  test "My team ticks every team member at once" do
    find("[data-reviews-target='peopleBtn']").click
    within(".kb-review-people") { find("[data-reviews-target='teamRow']").click }

    assert_selector "[data-reviews-target='peopleLabel']", text: "My team"
    assert_selector ".kb-pr-card", count: 1
    assert_selector ".kb-pr-card[data-snooze-key='acme/docs#2']"
  end

  test "Mine shows what ticking your own name shows, not only PRs you opened" do
    # Alice (alice-gh) wrote nothing here; she is asked to review the docs PR.
    click_button "Mine"
    assert_selector ".kb-pr-card", count: 1
    assert_selector ".kb-pr-card[data-snooze-key='acme/docs#2'] .kb-avatar-hit[data-login='alice-gh']"
  end

  test "a live refresh keeps the filters and an open menu as they were" do
    find("[data-reviews-target='peopleBtn']").click
    within(".kb-review-people") { find(".kb-people-row[data-login='bobby']").click }
    assert_selector ".kb-pr-card", count: 1

    create_review_pr(repo: "acme/server", number: 3, waiting_since: 9.days.ago,
                     reviews: [ { "login" => "bobby", "state" => "COMMENTED" } ])
    BoardBroadcasts.reviews

    assert_selector ".kb-pr-card[data-snooze-key='acme/server#3']", visible: :all
    assert_selector ".kb-pr-card", count: 2
    assert_selector ".kb-review-people", visible: true
    assert_selector ".kb-people-row[data-login='bobby'][data-on='1']"
  end
end
