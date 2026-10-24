class SyncCalendarFeedJob < ApplicationJob
  discard_on ActiveRecord::RecordNotFound

  def perform(feed_id, trigger = "hourly")
    CalendarFeed.find(feed_id).sync(trigger:)
  end
end
