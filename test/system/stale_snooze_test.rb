require "application_system_test_case"

class StaleSnoozeSystemTest < ApplicationSystemTestCase
  fixtures :epics, :issues, :sync_runs

  CARD = ".kb-card[data-tooltip-id='PG-11']".freeze

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice Adams" }
    )
    StaleSnooze.delete_all
    visit "/auth/google_oauth2/callback"
    visit "/"
    assert_selector CARD
  end

  def stale_count = find(".kb-counts .stale").text.to_i

  test "right-clicking a stale card snoozes it and takes it out of the stale counts" do
    before = stale_count
    assert_selector "#{CARD}[data-staleness='really']"

    find(CARD).right_click
    within "#kb-snooze" do
      assert_text "PG-11 has been in Review for"
      assert_button "Snooze #{LASER_FOCUS_CONFIG.board.snooze_days} days"
      fill_in "reason", with: "waiting on vendor"
      click_button "Snooze #{LASER_FOCUS_CONFIG.board.snooze_days} days"
    end

    assert_selector "#{CARD}[data-staleness='snoozed'] .kb-age .kb-snooze-icon"
    assert_no_selector "#kb-snooze", visible: true
    assert_equal before - 1, stale_count
    assert_selector ".kb-counts .snoozed", text: "1 snoozed"
    assert_selector ".kb-col[data-epic-key='PG-1'] .kb-col-snoozed", text: "1 snoozed"

    snooze = StaleSnooze.find_by!(jira_key: "PG-11")
    assert_equal "waiting on vendor", snooze.reason
    assert_equal "Alice Adams", snooze.snoozed_by
  end

  test "right-clicking a snoozed card shows the snooze and can lift it" do
    StaleSnooze.create!(jira_key: "PG-11", jira_status: "In Review", snoozed_until: 5.days.from_now,
                        snoozed_by: "Bob Brown", reason: "blocked on legal")
    visit "/"
    assert_selector "#{CARD}[data-staleness='snoozed']"

    find(CARD).right_click
    within "#kb-snooze" do
      assert_text "Snoozed until"
      assert_text "by Bob Brown · 5 days left"
      assert_text "blocked on legal"
      click_button "Unsnooze"
    end

    assert_selector "#{CARD}[data-staleness='really']"
    assert_no_selector ".kb-counts .snoozed"
    assert_equal 0, StaleSnooze.count
  end

  test "the tooltip of a snoozed card says who snoozed it and why" do
    StaleSnooze.create!(jira_key: "PG-11", jira_status: "In Review", snoozed_until: 5.days.from_now,
                        snoozed_by: "Bob Brown", reason: "blocked on legal")
    visit "/"
    find(CARD).hover
    within ".kb-tt" do
      assert_text "by Bob Brown until"
      assert_text "blocked on legal"
    end
  end

  test "Escape and Cancel close the menu without snoozing" do
    find(CARD).right_click
    assert_selector "#kb-snooze", visible: true
    find("#kb-snooze input[name='reason']").send_keys(:escape)
    assert_no_selector "#kb-snooze", visible: true

    find(CARD).right_click
    within("#kb-snooze") { click_button "Cancel" }
    assert_no_selector "#kb-snooze", visible: true
    assert_equal 0, StaleSnooze.count
  end

  test "fresh cards keep the browser menu" do
    fresh = find(".kb-card[data-tooltip-id='PG-10']", visible: :all)
    assert_nil fresh["data-snooze-key"]
  end
end
