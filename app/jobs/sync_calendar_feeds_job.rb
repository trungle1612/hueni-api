# Hourly fan-out (config/recurring.yml): one job per feed so a slow or broken feed doesn't block the others.
class SyncCalendarFeedsJob < ApplicationJob
  def perform
    ActiveJob.perform_all_later(CalendarFeed.ids.map { SyncCalendarFeedJob.new(it) })
  end
end
