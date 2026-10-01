class SyncCalendarFeedJob < ApplicationJob
  discard_on ActiveRecord::RecordNotFound

  def perform(feed_id)
    CalendarFeed.find(feed_id).sync
  end
end
