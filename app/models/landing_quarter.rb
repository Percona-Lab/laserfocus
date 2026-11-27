# An internal landing target: a quarter, or a whole year. Built by
# LandingCalendar from an idea's Time-ID.
class LandingQuarter
  include Comparable

  attr_reader :id, :year, :quarter, :codename

  def initialize(id, year, quarter, codename = nil)
    @id = id
    @year = year
    @quarter = quarter
    @codename = codename
  end

  def ongoing? = quarter.zero?

  def starts_on = ongoing? ? Date.new(year, 1, 1) : Date.new(year, (quarter - 1) * 3 + 1, 1)
  def ends_on   = ongoing? ? Date.new(year, 12, 31) : starts_on.next_month(3) - 1

  def cover?(date) = (starts_on..ends_on).cover?(date)

  def short_label = ongoing? ? "’#{year % 100} ongoing" : "Q#{quarter} ’#{year % 100}"
  def period_label = ongoing? ? "#{year} ongoing" : "#{year} Q#{quarter}"

  # First letter of the codename's last word; without a codename, Q or O.
  def letter = codename.present? ? codename.split.last[0].upcase : (ongoing? ? "O" : "Q")
  def animal = codename.present? ? codename.split.last : nil
  def name = codename.presence || period_label

  def <=>(other)
    return nil unless other.is_a?(LandingQuarter)
    [ ends_on, id ] <=> [ other.ends_on, other.id ]
  end

  def ==(other) = other.is_a?(LandingQuarter) && other.id == id
  alias eql? ==
  def hash = id.hash
end
