require "test_helper"

class BoardControllerTest < ActionDispatch::IntegrationTest
  fixtures :epics, :issues

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    get "/auth/google_oauth2/callback"
  end

  test "renders columns for active epics" do
    get root_path
    assert_response :success
    assert_select ".kb-col", count: 2
  end

  test "redirects to login when unauthenticated" do
    reset!
    get root_path
    assert_redirected_to "/login"
  end

  test "renders a card per active issue" do
    get root_path
    assert_select ".kb-card"
  end

  test "renders columns in the persisted board order" do
    BoardOrder.instance.update!(column_order: %w[PG-2 PG-1])
    get root_path
    assert_response :success
    pg2_pos = response.body.index('id="kb-col-PG-2"')
    pg1_pos = response.body.index('id="kb-col-PG-1"')
    assert pg2_pos && pg1_pos && pg2_pos < pg1_pos,
      "expected PG-2 column to render before PG-1 (PG-2 at #{pg2_pos.inspect}, PG-1 at #{pg1_pos.inspect})"
  end

  test "merged cookie renders a single middle section per column" do
    cookies[:board_group_mode] = "merged"
    get root_path
    assert_response :success
    assert_select "#kb-col-PG-1 button.kb-stack-btn[data-status=?]", "merged", count: 1
    assert_select "#kb-col-PG-1 button.kb-stack-btn[data-status=?]", "in_progress", count: 0
    assert_select "#kb-col-PG-1 .kb-stack-label", text: /IN PROGRESS/
  end

  test "unknown group mode cookie falls back to staleness grouping" do
    cookies[:board_group_mode] = "bogus"
    get root_path
    assert_response :success
    assert_select "#kb-col-PG-1 button.kb-stack-btn[data-status=?]", "in_progress", count: 1
    assert_select "#kb-col-PG-1 button.kb-stack-btn[data-status=?]", "review", count: 1
  end

  test "definition cookie reorders middle sections by configured status order" do
    cookies[:board_group_mode] = "definition"
    get root_path
    assert_response :success
    statuses = css_select("#kb-col-PG-1 .kb-stack-btn[data-status]").map { |n| n["data-status"] }
    assert_equal %w[in_progress review], statuses
  end

  test "renders the group mode chooser with the active mode marked" do
    cookies[:board_group_mode] = "merged"
    get root_path
    assert_select ".kb-group-mode button[data-mode=merged][data-on='1']", count: 1
    assert_select ".kb-group-mode button[data-mode=staleness][data-on='0']", count: 1
    assert_select ".kb-group-mode button[data-mode=definition][data-on='0']", count: 1
  end

  test "bogus cookie marks the staleness chooser option active" do
    cookies[:board_group_mode] = "bogus"
    get root_path
    assert_select ".kb-group-mode button[data-mode=staleness][data-on='1']", count: 1
    assert_select ".kb-group-mode button[data-mode=merged][data-on='0']", count: 1
  end

  test "renders collapsed columns inside a stack" do
    BoardOrder.instance.update!(column_order: %w[PG-1 PG-2], collapsed_columns: %w[PG-1 PG-2])
    get root_path
    assert_response :success
    assert_select ".kb-col-stack", count: 1
    assert_select ".kb-col-stack .kb-col[data-collapsed='1']", count: 2
    assert_select "#kb-col-PG-1 .kb-card", count: 0
  end

  test "expand_all param renders collapsed columns open with a chip" do
    BoardOrder.instance.update!(collapsed_columns: %w[PG-1])
    get root_path, params: { expand_all: 1 }
    assert_response :success
    assert_select ".kb-col-stack", count: 0
    assert_select "#kb-col-PG-1 .kb-card"
    assert_select "#kb-col-PG-1 .kb-col-collapsed-chip", count: 1
    assert_select "#kb-col-PG-2 .kb-col-collapsed-chip", count: 0
    assert_select ".kb-expand-all-hint", count: 1
    assert_select "#kb-col-PG-1[data-collapsed]", count: 0
    assert_select "#kb-col-PG-1 .kb-col-fold-btn[data-collapsed='1']", count: 1
    assert_equal %w[PG-1], BoardOrder.instance.reload.collapsed_columns
  end

  test "expand_all=0 is treated as off" do
    BoardOrder.instance.update!(collapsed_columns: %w[PG-1])
    get root_path, params: { expand_all: 0 }
    assert_response :success
    assert_select ".kb-col[data-collapsed='1']", count: 1
    assert_select ".kb-expand-all-hint", count: 0
  end

  test "expand_all=false is treated as off" do
    BoardOrder.instance.update!(collapsed_columns: %w[PG-1])
    get root_path, params: { expand_all: "false" }
    assert_response :success
    assert_select ".kb-col[data-collapsed='1']", count: 1
  end
end
