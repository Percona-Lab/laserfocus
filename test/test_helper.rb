ENV["RAILS_ENV"] ||= "test"
ENV["GOOGLE_CLIENT_ID"] = "test-id"
ENV["GOOGLE_CLIENT_SECRET"] = "test-secret"
ENV["JIRA_BASE_URL"] = "https://example.atlassian.net"
ENV["JIRA_EMAIL"] = "jira@example.com"
ENV["JIRA_API_TOKEN"] = "test-token"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
