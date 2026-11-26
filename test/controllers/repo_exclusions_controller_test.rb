require "test_helper"

class RepoExclusionsControllerTest < ActionDispatch::IntegrationTest
  include ReviewPrFactory

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "Alice@Example.com", name: "Alice Adams" }
    )
    get "/auth/google_oauth2/callback"
  end

  test "excludes a watched repo for the signed-in viewer only, once" do
    2.times { patch "/repo_exclusion", params: { repo: "Acme/Docs", excluded: true }, as: :json }
    assert_response :no_content

    assert_equal Set["acme/docs"], RepoExclusion.repos_for("alice@example.com")
    assert_equal 1, RepoExclusion.count
    assert_empty RepoExclusion.repos_for("bob@example.com")
  end

  test "includes it again" do
    RepoExclusion.create!(user_email: "alice@example.com", repo: "acme/docs")
    RepoExclusion.create!(user_email: "bob@example.com", repo: "acme/docs")
    patch "/repo_exclusion", params: { repo: "acme/docs", excluded: false }, as: :json

    assert_response :no_content
    assert_empty RepoExclusion.repos_for("alice@example.com")
    assert_equal Set["acme/docs"], RepoExclusion.repos_for("bob@example.com")
  end

  test "refuses a repo that is not watched" do
    patch "/repo_exclusion", params: { repo: "evil/repo", excluded: true }, as: :json
    assert_response :not_found
    assert_equal 0, RepoExclusion.count
  end

  test "the viewer's pages leave out the excluded repo, tab count included" do
    create_review_pr(repo: "acme/server", number: 1, waiting_since: 9.days.ago)
    create_review_pr(repo: "acme/docs", number: 2, waiting_since: 9.days.ago)
    patch "/repo_exclusion", params: { repo: "acme/docs", excluded: true }, as: :json

    get "/reviews"
    assert_select ".kb-pr-card", count: 1
    assert_select ".kb-pr-card[data-repo='acme/docs']", count: 0
    assert_select ".kb-filter-row[data-repo='acme/docs'][data-excluded='1']"
    assert_select ".kb-filter-row[data-repo='acme/server'][data-excluded='0']"
    assert_select "a[href='/reviews'] .kb-tab-badge", text: "1"
  end
end
