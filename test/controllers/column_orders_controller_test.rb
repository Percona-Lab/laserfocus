require "test_helper"
require "turbo/broadcastable/test_helper"

class ColumnOrdersControllerTest < ActionDispatch::IntegrationTest
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

  test "persists the new order" do
    patch "/column_order", params: { order: [ "PG-2", "UNPLANNED", "PG-1" ] }, as: :json
    assert_response :no_content
    assert_equal [ "PG-2", "UNPLANNED", "PG-1" ], BoardOrder.instance.column_order
  end

  test "filters unknown and removed epic keys" do
    patch "/column_order", params: { order: [ "PG-404", "PG-9", "PG-2", "PG-1" ] }, as: :json
    assert_response :no_content
    assert_equal [ "PG-2", "PG-1" ], BoardOrder.instance.column_order
  end

  test "broadcasts the board after saving" do
    assert_turbo_stream_broadcasts("board") do
      patch "/column_order", params: { order: [ "PG-2", "PG-1" ] }, as: :json
    end
  end

  test "requires login" do
    reset!
    patch "/column_order", params: { order: [ "PG-1" ] }, as: :json
    assert_redirected_to "/login"
  end
end
