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
end
