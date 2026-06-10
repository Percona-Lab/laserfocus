require "test_helper"
require "webmock/minitest"

class JiraClientTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!
  end

  test "search returns issues matching JQL" do
    body = {
      "issues" => [
        { "key" => "PG-1", "fields" => { "summary" => "Foo" } }
      ],
      "total" => 1,
      "startAt" => 0,
      "maxResults" => 50
    }.to_json

    stub_request(:get, %r{/rest/api/2/search})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    client = JiraClient.new
    issues = client.search_all("project = PG")
    assert_equal "PG-1", issues.first.key
  end

  test "requests max page size of 100" do
    body = { "issues" => [], "total" => 0 }.to_json
    stub_request(:get, %r{/rest/api/2/search})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    JiraClient.new.search_all("project = PG")

    assert_requested :get, %r{maxResults=100}
  end

  test "retries on 429 honoring Retry-After header" do
    success_body = {
      "issues" => [ { "key" => "PG-1", "fields" => { "summary" => "Foo" } } ],
      "total" => 1
    }.to_json

    stub_request(:get, %r{/rest/api/2/search})
      .to_return(
        { status: 429, headers: { "Retry-After" => "1" }, body: "" },
        { status: 200, body: success_body, headers: { "Content-Type" => "application/json" } }
      )

    slept = with_stubbed_pause do |slept_log|
      issues = JiraClient.new.search_all("project = PG")
      assert_equal "PG-1", issues.first.key
      slept_log
    end
    assert_equal [ 1 ], slept
  end

  test "gives up after MAX_RETRIES on persistent 429" do
    stub_request(:get, %r{/rest/api/2/search})
      .to_return(status: 429, headers: { "Retry-After" => "1" }, body: "")

    slept = with_stubbed_pause do |slept_log|
      error = assert_raises(JIRA::HTTPError) do
        JiraClient.new.search_all("project = PG")
      end
      assert_equal "429", error.response.code
      slept_log
    end
    assert_equal JiraClient::MAX_RETRIES, slept.size
  end

  private

  def with_stubbed_pause
    slept = []
    original = JiraClient.method(:pause)
    JiraClient.singleton_class.send(:define_method, :pause) { |s| slept << s }
    yield slept
  ensure
    JiraClient.singleton_class.send(:define_method, :pause, original)
  end

  test "retry_after_seconds parses numeric Retry-After" do
    response = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests")
    response["Retry-After"] = "7"
    assert_equal 7, JiraClient.retry_after_seconds(response, 1)
  end

  test "retry_after_seconds falls back to exponential backoff when header absent" do
    response = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests")
    assert_equal 2, JiraClient.retry_after_seconds(response, 1)
    assert_equal 4, JiraClient.retry_after_seconds(response, 2)
    assert_equal 8, JiraClient.retry_after_seconds(response, 3)
  end

  test "retry_after_seconds clamps at MAX_RETRY_WAIT" do
    response = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests")
    response["Retry-After"] = "9999"
    assert_equal JiraClient::MAX_RETRY_WAIT, JiraClient.retry_after_seconds(response, 1)
  end
end
