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

  test "provisional_meta returns the cool-blue paper and accent" do
    assert_equal({ paper: "#eaf1ff", accent: "#2563eb" }, provisional_meta)
  end
end
