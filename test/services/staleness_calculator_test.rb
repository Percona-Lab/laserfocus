require "test_helper"

class StalenessCalculatorTest < ActiveSupport::TestCase
  def calc(now: Time.utc(2026, 6, 9, 12, 0, 0),
           somewhat: 7, really: 21,
           ignore_for_new: true)
    StalenessCalculator.new(now: now,
                            somewhat_days: somewhat,
                            really_days: really,
                            ignore_for_new: ignore_for_new)
  end

  test "fresh when transitioned recently" do
    assert_equal :fresh,
                 calc.bucket(transitioned_at: Time.utc(2026, 6, 5),
                             display_status: "in_progress")
  end

  test "somewhat when between thresholds" do
    assert_equal :somewhat,
                 calc.bucket(transitioned_at: Time.utc(2026, 5, 25),
                             display_status: "in_progress")
  end

  test "really when older than really_days" do
    assert_equal :really,
                 calc.bucket(transitioned_at: Time.utc(2026, 5, 1),
                             display_status: "in_progress")
  end

  test "new issues skip staleness when ignore_for_new is true" do
    assert_equal :fresh,
                 calc.bucket(transitioned_at: Time.utc(2024, 1, 1),
                             display_status: "new")
  end

  test "done issues are always fresh regardless of age" do
    assert_equal :fresh,
                 calc.bucket(transitioned_at: Time.utc(2024, 1, 1),
                             display_status: "done")
  end
end
