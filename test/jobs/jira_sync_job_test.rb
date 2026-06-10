require "test_helper"

class JiraSyncJobTest < ActiveSupport::TestCase
  setup do
    User.touch_now!
  end

  # Replace JiraSync.new with a lambda producing the desired result for the
  # duration of the block. Restores the original method afterward.
  def with_stub_jira_sync(result_block)
    JiraSync.singleton_class.send(:alias_method, :__orig_new, :new)
    JiraSync.singleton_class.send(:define_method, :new) { |*_, **_| result_block.call }
    yield
  ensure
    JiraSync.singleton_class.send(:remove_method, :new)
    JiraSync.singleton_class.send(:alias_method, :new, :__orig_new)
    JiraSync.singleton_class.send(:remove_method, :__orig_new)
  end

  test "calls JiraSync.run! in active mode" do
    runs_before = SyncRun.ok.count
    fake = Object.new
    def fake.run!
      SyncRun.create!(started_at: Time.current, ok: true)
    end

    with_stub_jira_sync(-> { fake }) do
      JiraSyncJob.new.perform
    end

    assert_equal runs_before + 1, SyncRun.ok.count
  end

  test "skips sync in idle mode when last successful sync is recent" do
    User.singleton.update!(last_seen_at: 1.hour.ago)
    SyncRun.create!(started_at: 5.minutes.ago, finished_at: 5.minutes.ago, ok: true)

    sync_invoked = false
    fake_raising = Object.new
    define_singleton_method = ->(obj) {
      obj.define_singleton_method(:run!) { sync_invoked = true; raise "should not call" }
      obj
    }

    with_stub_jira_sync(-> { define_singleton_method.call(Object.new) }) do
      JiraSyncJob.new.perform
    end

    assert_not sync_invoked
  end
end
