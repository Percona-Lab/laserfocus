require "test_helper"

class BoardHelperTest < ActionView::TestCase
  test "labels derive from titleized status ids" do
    assert_equal "Review", state_meta("review")[:label]
    assert_equal "In Progress", state_meta("in_progress")[:label]
  end

  test "unconfigured ids titleize" do
    assert_equal "Doc", state_meta("doc")[:label]
  end

  test "known ids keep their colors" do
    assert_equal "#8b5cf6", state_meta("review")[:color]
    assert_equal "#94a3b8", state_meta("new")[:color]
  end

  test "state_meta has no short variant" do
    assert_not state_meta("review").key?(:short)
  end

  test "column_accent picks a stable palette entry per key" do
    assert_equal "#0d9488", column_accent("PG-1")
    assert_equal column_accent("PG-1"), column_accent("PG-1")
  end

  test "provisional_meta returns the cool-blue paper and accent" do
    assert_equal({ paper: "#eaf1ff", accent: "#2563eb" }, provisional_meta)
  end

  test "snoozed tickets get a neutral style and their own label" do
    assert_equal "snoozed", staleness_label(:snoozed)
    assert_equal "#ffffff", staleness_meta(:snoozed)[:paper]
    assert_equal staleness_meta(:fresh)[:border], staleness_meta(:snoozed)[:border]
  end

  test "snooze_summary names who, until when and why" do
    s = StaleSnooze.new(snoozed_by: "Kai Wagner", snoozed_until: Time.zone.local(2026, 10, 5, 12), reason: "waiting on vendor")
    assert_equal "by Kai Wagner until Oct 5 · waiting on vendor", snooze_summary(s)
    s.reason = nil
    assert_equal "by Kai Wagner until Oct 5", snooze_summary(s)
  end
end
