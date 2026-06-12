require "application_system_test_case"

class GroupModeTest < ApplicationSystemTestCase
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

  test "unified mode merges middle sections and persists across reload" do
    assert_equal %w[review in_progress], middle_statuses("PG-1")

    click_button "Unified"
    assert_selector "#kb-col-PG-1 .kb-stack-btn[data-status='merged']"
    assert_equal %w[merged], middle_statuses("PG-1")
    assert_no_selector "#kb-col-PG-1 .kb-divider", visible: :all

    visit "/"
    assert_selector "main.kb-board#board-root"
    assert_equal %w[merged], middle_statuses("PG-1")
  end

  test "status order mode orders sections by configured status order" do
    click_button "Status order"
    assert_selector ".kb-group-mode button[data-mode='definition'][data-on='1']"
    assert_equal %w[in_progress review], middle_statuses("PG-1")
  end

  test "broadcast refresh keeps the session's chosen mode" do
    click_button "Unified"
    assert_selector "#kb-col-PG-1 .kb-stack-btn[data-status='merged']"
    assert_no_selector "#kb-col-PG-1 .kb-stack-btn[data-status='review']", visible: :all

    issues(:fresh_in_progress).update!(summary: "Updated title")
    broadcast_board

    assert_selector %([data-tooltip-id="PG-10"][data-tooltip-title="Updated title"]), visible: :all
    assert_selector "#kb-col-PG-1 .kb-stack-btn[data-status='merged']"
    assert_no_selector "#kb-col-PG-1 .kb-stack-btn[data-status='review']", visible: :all
  end

  test "search dimming survives a broadcast refresh" do
    # headless Chrome here can't deliver real keystrokes; dispatch input directly
    page.execute_script(<<~JS)
      const input = document.querySelector("input.kb-search");
      input.value = "PG-10";
      input.dispatchEvent(new Event("input", { bubbles: true }));
    JS
    assert_selector %([data-tooltip-id="PG-11"][data-dim="1"]), visible: :all

    issues(:fresh_in_progress).update!(summary: "Touched by sync")
    broadcast_board

    assert_selector %([data-tooltip-id="PG-10"][data-tooltip-title="Touched by sync"]), visible: :all
    assert_selector %([data-tooltip-id="PG-11"][data-dim="1"]), visible: :all
  end

  private

  def middle_statuses(epic_key)
    all("#kb-col-#{epic_key} .kb-stack-btn[data-status]", visible: :all).map { |b| b["data-status"] }
  end
end
