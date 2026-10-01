require "test_helper"

class CalendarFeedSyncTest < ActiveSupport::TestCase
  URL = "https://1.1.1.1/calendar/ical/42.ics?s=token"

  setup do
    travel_to Time.zone.local(2026, 10, 5, 12)
    @feed = CalendarFeed.create!(room: rooms(:garden), url: URL, provider: "airbnb")
  end

  def stub_feed(file = nil, body: file_fixture(file).read, status: 200)
    stub_request(:get, URL).to_return(status:, body:)
  end

  def ical_booking(uid, start_date, end_date)
    @feed.bookings.create!(room: @feed.room, uid:, start_date:, end_date:, source: "ical")
  end

  def assert_failed_without_changes(pattern)
    assert_no_changes -> { Booking.order(:id).pluck(:id, :start_date, :end_date) } do
      assert_not @feed.sync
    end
    @feed.reload
    assert_match pattern, @feed.last_error
    assert_equal Time.current, @feed.last_error_at
    assert_nil @feed.last_synced_at
  end

  test "imports Airbnb reservations and blocks as confirmed ical bookings, skipping past events" do
    stub_feed("airbnb.ics")

    assert @feed.sync

    rows = @feed.bookings.order(:start_date).pluck(:uid, :start_date, :end_date, :status, :source, :room_id)
    assert_equal [
      [ "1418fb94e984-reserved-1@airbnb.com", Date.new(2026, 10, 10), Date.new(2026, 10, 12), "confirmed", "ical", rooms(:garden).id ],
      [ "1418fb94e984-blocked-1@airbnb.com", Date.new(2026, 10, 20), Date.new(2026, 10, 22), "confirmed", "ical", rooms(:garden).id ]
    ], rows
    assert_equal Time.current, @feed.reload.last_synced_at
    assert_nil @feed.last_error
  end

  test "imports Booking.com closures and converts UTC date-times to Huế dates" do
    stub_feed("booking.ics")

    assert @feed.sync

    assert_equal [
      [ Date.new(2026, 10, 15), Date.new(2026, 10, 17) ],
      [ Date.new(2026, 10, 25), Date.new(2026, 10, 27) ] # 17:00 UTC = 00:00 next day in Huế
    ], @feed.bookings.order(:start_date).pluck(:start_date, :end_date)
  end

  test "updates changed dates instead of duplicating" do
    existing = ical_booking("1418fb94e984-reserved-1@airbnb.com", "2026-10-09", "2026-10-11")
    stub_feed("airbnb.ics")

    @feed.sync

    assert_equal [ Date.new(2026, 10, 10), Date.new(2026, 10, 12) ], existing.reload.slice(:start_date, :end_date).values
    assert_equal 2, @feed.bookings.count
  end

  test "deletes future bookings missing from the feed but keeps past ones" do
    cancelled = ical_booking("gone@airbnb.com", "2026-10-28", "2026-10-30")
    ongoing = ical_booking("ongoing@airbnb.com", "2026-10-04", "2026-10-06")
    past = ical_booking("past@airbnb.com", "2026-10-01", "2026-10-05") # checked out today
    stub_feed("airbnb.ics")

    @feed.sync

    assert_not Booking.exists?(cancelled.id)
    assert_not Booking.exists?(ongoing.id)
    assert Booking.exists?(past.id)
  end

  test "empty valid calendar removes all future bookings of this feed only" do
    ical_booking("gone@airbnb.com", "2026-10-28", "2026-10-30")
    stub_feed("empty.ics")

    assert @feed.sync

    assert_equal 0, @feed.bookings.count
    assert Booking.exists?(bookings(:limdim_confirmed).id)
  end

  test "HTTP error changes no bookings and records the error" do
    ical_booking("keep@airbnb.com", "2026-10-28", "2026-10-30")
    stub_feed(body: "oops", status: 500)
    assert_failed_without_changes(/500/)
  end

  test "timeout changes no bookings" do
    ical_booking("keep@airbnb.com", "2026-10-28", "2026-10-30")
    stub_request(:get, URL).to_timeout
    assert_failed_without_changes(/timeout|timed out/i)
  end

  test "non-calendar body changes no bookings" do
    ical_booking("keep@airbnb.com", "2026-10-28", "2026-10-30")
    stub_feed(body: "<html>Login</html>")
    assert_failed_without_changes(/iCalendar/)
  end

  test "body over 2 MB is rejected" do
    stub_feed(body: "x" * (2.megabytes + 1))
    assert_failed_without_changes(/2 MB/)
  end

  test "follows up to 3 redirects to public hosts" do
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => "https://8.8.8.8/a.ics" })
    stub_request(:get, "https://8.8.8.8/a.ics").to_return(body: file_fixture("empty.ics").read)
    assert @feed.sync
  end

  test "rejects more than 3 redirects" do
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => URL })
    assert_failed_without_changes(/redirect/)
  end

  test "rejects redirects to private addresses" do
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => "http://127.0.0.1/admin" })
    assert_failed_without_changes(/public/)
    assert_not_requested :get, "http://127.0.0.1/admin"
  end

  test "busts the vacancy cache after removing cancelled bookings" do
    original, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    ical_booking("gone@airbnb.com", "2026-10-04", "2026-10-06") # garden booked today, limdim free
    assert_equal 1, Vacancy.cached[:places]["tomo-homestay"][:left]

    stub_feed("empty.ics")
    @feed.sync # delete_all skips callbacks, so sync must bust explicitly

    assert_equal 2, Vacancy.cached[:places]["tomo-homestay"][:left]
  ensure
    Rails.cache = original
  end

  test "job syncs the feed and ignores deleted feeds" do
    stub_feed("airbnb.ics")
    SyncCalendarFeedJob.perform_now(@feed.id)
    assert_equal 2, @feed.bookings.count

    assert_nothing_raised { SyncCalendarFeedJob.perform_now(0) }
  end
end
