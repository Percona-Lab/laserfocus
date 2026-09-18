require "test_helper"
require "turbo/broadcastable/test_helper"

class ColumnCollapsesControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  fixtures :epics, :issues, :sync_runs

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    get "/auth/google_oauth2/callback"
  end

  test "collapses a known column" do
    patch "/column_collapse", params: { key: "PG-1", collapsed: true }, as: :json
    assert_response :no_content
    assert_equal [ "PG-1" ], BoardOrder.instance.collapsed_columns
  end

  test "does not duplicate an already collapsed key" do
    BoardOrder.instance.update!(collapsed_columns: [ "PG-1" ])
    patch "/column_collapse", params: { key: "PG-1", collapsed: true }, as: :json
    assert_response :no_content
    assert_equal [ "PG-1" ], BoardOrder.instance.collapsed_columns
  end

  test "expands a collapsed column" do
    BoardOrder.instance.update!(collapsed_columns: [ "PG-1", "PG-2" ])
    patch "/column_collapse", params: { key: "PG-1", collapsed: false }, as: :json
    assert_response :no_content
    assert_equal [ "PG-2" ], BoardOrder.instance.collapsed_columns
  end

  test "accepts the unplanned sentinel" do
    patch "/column_collapse", params: { key: "UNPLANNED", collapsed: true }, as: :json
    assert_response :no_content
    assert_equal [ "UNPLANNED" ], BoardOrder.instance.collapsed_columns
  end

  test "ignores unknown and removed epic keys without broadcasting" do
    assert_no_turbo_stream_broadcasts("board") do
      patch "/column_collapse", params: { key: "PG-404", collapsed: true }, as: :json
      assert_response :no_content
      patch "/column_collapse", params: { key: "PG-9", collapsed: true }, as: :json
      assert_response :no_content
    end
    assert_equal 0, BoardOrder.count
  end

  test "prunes keys of removed epics on save" do
    BoardOrder.instance.update!(collapsed_columns: [ "PG-9", "PG-2" ])
    patch "/column_collapse", params: { key: "PG-1", collapsed: true }, as: :json
    assert_equal [ "PG-2", "PG-1" ], BoardOrder.instance.collapsed_columns
  end

  test "does not broadcast when nothing changed" do
    BoardOrder.instance.update!(collapsed_columns: [ "PG-1" ])
    assert_no_turbo_stream_broadcasts("board") do
      patch "/column_collapse", params: { key: "PG-1", collapsed: true }, as: :json
    end
  end

  test "broadcasts the board after saving" do
    assert_turbo_stream_broadcasts("board") do
      patch "/column_collapse", params: { key: "PG-1", collapsed: true }, as: :json
    end
  end

  test "requires login" do
    reset!
    patch "/column_collapse", params: { key: "PG-1", collapsed: true }, as: :json
    assert_redirected_to "/login"
  end
end
