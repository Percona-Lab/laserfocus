require "test_helper"

# Uses a made-up layout; the real one lives only in the deployment config.
class LandingCalendarTest < ActiveSupport::TestCase
  def calendar(codenames = {}) = LandingCalendar.new(layout: "QYY", codenames: codenames)

  test "reads a Time-ID by the configured layout" do
    q = calendar(127 => "Brave Bear").quarter(127)

    assert_equal 2027, q.year
    assert_equal 1, q.quarter
    assert_equal Date.new(2027, 1, 1), q.starts_on
    assert_equal Date.new(2027, 3, 31), q.ends_on
    assert_equal "Q1 ’27", q.short_label
    assert_equal "Brave Bear", q.codename
    assert_equal "B", q.letter
  end

  test "quarter 0 is the whole year" do
    q = calendar.quarter(27)

    assert q.ongoing?
    assert_equal Date.new(2027, 12, 31), q.ends_on
    assert_equal "’27 ongoing", q.short_label
  end

  test "reads the float Jira hands back and rejects what does not fit" do
    assert_equal 426, calendar.quarter("426.0").id
    assert_nil calendar.quarter(527)
    assert_nil calendar.quarter(1234)
    assert_nil calendar.quarter("abc")
    assert_nil LandingCalendar.new(layout: nil).quarter(426)
  end

  test "finds the quarter a day falls in" do
    assert_equal 426, calendar.containing(Date.new(2026, 11, 27)).id
    assert_equal 127, calendar.containing(Date.new(2027, 2, 1)).id
    assert calendar.quarter(426) < calendar.quarter(127)
  end

  test "learns each Time-ID's codename from the ideas that carry it" do
    ideas = [
      DiscoveryIdea.new(time_id: 127, codename: "Brave Bear"),
      DiscoveryIdea.new(time_id: 127, codename: "Brave Bear"),
      DiscoveryIdea.new(time_id: 127, codename: "Amber Ant"),
      DiscoveryIdea.new(time_id: 426, codename: "Amber Ant"),
      DiscoveryIdea.new(time_id: 227, codename: nil)
    ]

    assert_equal({ 127 => "Brave Bear", 426 => "Amber Ant" }, LandingCalendar.learn_codenames(ideas))
  end
end
