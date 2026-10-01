require "test_helper"
require "fugit"

class SyncCalendarFeedsJobTest < ActiveJob::TestCase
  test "enqueues one sync job per feed" do
    second = CalendarFeed.create!(room: rooms(:garden), url: "https://1.1.1.1/b.ics", provider: "booking")

    SyncCalendarFeedsJob.perform_now

    assert_enqueued_jobs 2, only: SyncCalendarFeedJob
    assert_enqueued_with job: SyncCalendarFeedJob, args: [ calendar_feeds(:limdim_airbnb).id ]
    assert_enqueued_with job: SyncCalendarFeedJob, args: [ second.id ]
  end

  test "is scheduled hourly in production" do
    task = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "sync_calendar_feeds")

    assert_equal SyncCalendarFeedsJob, task["class"].constantize
    assert_equal 3600, Fugit.parse(task["schedule"]).rough_frequency
  end
end
