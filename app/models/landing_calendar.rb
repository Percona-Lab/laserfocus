# Turns Time-IDs into LandingQuarters. How a Time-ID reads is not written down
# here: it comes from discovery.time_id_layout in the deployment's config, one
# character per digit, Y for the year and Q for the quarter.
#
# Codenames are learned from Discovery: the Codename most ideas carry for a
# given Time-ID names that Time-ID, so new ones need no config change.
class LandingCalendar
  attr_reader :codenames

  def self.build(discovery, ideas)
    new(layout: discovery.time_id_layout, codenames: learn_codenames(ideas))
  end

  def self.learn_codenames(ideas)
    ideas.select { |i| i.time_id && i.codename.present? }
         .group_by(&:time_id)
         .transform_values { |list| list.map(&:codename).tally.max_by { |name, count| [ count, name ] }.first }
  end

  def initialize(layout:, codenames: {})
    @layout = layout.to_s.strip.upcase
    @codenames = codenames
  end

  def quarter(id)
    digits = id.to_s.strip.sub(/\.0+\z/, "")
    return nil unless digits.match?(/\A\d+\z/) && @layout.present?
    digits = digits.rjust(@layout.length, "0")
    return nil unless digits.length == @layout.length

    year = +""
    part = +""
    @layout.each_char.with_index do |char, i|
      case char
      when "Y" then year << digits[i]
      when "Q" then part << digits[i]
      else return nil
      end
    end
    return nil if year.empty? || part.length != 1 || !(0..4).cover?(part.to_i)

    full_year = year.length <= 2 ? 2000 + year.to_i : year.to_i
    LandingQuarter.new(digits.to_i, full_year, part.to_i, @codenames[digits.to_i])
  end

  # The quarter a day falls in.
  def containing(date)
    year_digits = @layout.count("Y")
    return nil if year_digits.zero?

    year = (date.year % 10**year_digits).to_s.rjust(year_digits, "0").chars
    quarter(@layout.chars.map { |char| char == "Y" ? year.shift : ((date.month - 1) / 3 + 1).to_s }.join)
  end

  def quarter_for_codename(name)
    id = name.present? ? codenames.key(name) : nil
    id && quarter(id)
  end
end
