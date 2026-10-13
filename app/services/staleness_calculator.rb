class StalenessCalculator
  def initialize(now:, somewhat_days:, really_days:, ignore_for_new: true, lead: 0,
                 new_display_statuses: [ "new" ], done_display_statuses: [ "done" ])
    @now = now
    @somewhat = somewhat_days.days - lead
    @really   = really_days.days - lead
    @ignore_for_new = ignore_for_new
    @new_statuses = new_display_statuses
    @done_statuses = done_display_statuses
  end

  def bucket(transitioned_at:, display_status:)
    return :fresh if @ignore_for_new && @new_statuses.include?(display_status)
    return :fresh if @done_statuses.include?(display_status)
    age = @now - transitioned_at
    return :really   if age >= @really
    return :somewhat if age >= @somewhat
    :fresh
  end
end
