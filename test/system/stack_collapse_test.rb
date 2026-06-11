require "application_system_test_case"

class StackCollapseTest < ApplicationSystemTestCase
  fixtures :epics, :issues, :sync_runs

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    visit "/auth/google_oauth2/callback"
    visit "/"
    assert_selector "main.kb-board#board-root"
  end

  # PG-1 column: PG-10 (In Progress), PG-11 (In Review), PG-12 (To Do), PG-13 (Done)

  test "middle section toggle hides its cards" do
    within ".kb-col[data-epic-key='PG-1']" do
      assert_selector "[data-tooltip-id='PG-10']"
      find("[data-stack-target='middleBtn'][data-status='in_progress']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
    end
  end

  test "clicking a collapsed middle toggle reveals its cards" do
    within ".kb-col[data-epic-key='PG-1']" do
      find("[data-stack-target='middleBtn'][data-status='in_progress']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
      find("[data-stack-target='middleBtn'][data-status='in_progress']").click
      assert_selector "[data-tooltip-id='PG-10']"
    end
  end

  test "collapse-all button hides all middle sections" do
    within ".kb-col[data-epic-key='PG-1']" do
      assert_selector "[data-tooltip-id='PG-10']"
      assert_selector "[data-tooltip-id='PG-11']"
      find("[data-stack-target='collapseAllBtn']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
      assert_no_selector "[data-tooltip-id='PG-11']"
    end
  end

  test "collapse-all then expand-all restores middle sections" do
    within ".kb-col[data-epic-key='PG-1']" do
      find("[data-stack-target='collapseAllBtn']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
      find("[data-stack-target='collapseAllBtn']").click
      assert_selector "[data-tooltip-id='PG-10']"
      assert_selector "[data-tooltip-id='PG-11']"
    end
  end

  test "middle collapse state survives a Turbo broadcast" do
    within ".kb-col[data-epic-key='PG-1']" do
      find("[data-stack-target='middleBtn'][data-status='in_progress']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
    end

    broadcast_board

    within ".kb-col[data-epic-key='PG-1']" do
      assert_no_selector "[data-tooltip-id='PG-10']"
      assert_selector "[data-tooltip-id='PG-11']"
    end
  end

  private

  def broadcast_board
    Turbo::StreamsChannel.broadcast_render_to(
      "board",
      partial: "board/board_morph",
      locals: { presenter: build_presenter, last_sync: SyncRun.ok.most_recent.first }
    )
  end

  def build_presenter
    BoardPresenter.new(
      epics: Epic.active.ordered.includes(:issues),
      orphan_issues: Issue.active.orphan,
      status_map: LASER_FOCUS_CONFIG.board.status_map,
      new_statuses: LASER_FOCUS_CONFIG.board.new_statuses,
      done_statuses: LASER_FOCUS_CONFIG.board.done_statuses,
      staleness: StalenessCalculator.new(
        now: Time.current,
        somewhat_days: LASER_FOCUS_CONFIG.board.staleness.somewhat_days,
        really_days: LASER_FOCUS_CONFIG.board.staleness.really_days,
        ignore_for_new: LASER_FOCUS_CONFIG.board.ignore_staleness_for_new_issues,
        new_display_statuses: LASER_FOCUS_CONFIG.board.new_statuses,
        done_display_statuses: LASER_FOCUS_CONFIG.board.done_statuses
      )
    )
  end
end
