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

  test "re-sync keeps check-in and guest count" do
    existing = ical_booking("1418fb94e984-reserved-1@airbnb.com", "2026-10-09", "2026-10-11")
    existing.update_columns(checked_in_at: Time.current, guests: 2)
    stub_feed("airbnb.ics")

    assert @feed.sync

    existing.reload
    assert_equal Time.current, existing.checked_in_at
    assert_equal 2, existing.guests
  end

  test "sync logs adds, moves and removals as the provider; a quiet re-sync logs nothing" do
    moved = ical_booking("1418fb94e984-reserved-1@airbnb.com", "2026-10-09", "2026-10-11")
    gone = ical_booking("gone@airbnb.com", "2026-10-28", "2026-10-30")
    stub_feed("airbnb.ics")
    before = PaperTrail::Version.maximum(:id)

    assert @feed.sync

    versions = PaperTrail::Version.where(id: before.next..).order(:id)
    assert_equal [ [ "Booking", "update", moved.id ], [ "Booking", "create", @feed.bookings.find_by!(uid: "1418fb94e984-blocked-1@airbnb.com").id ], [ "Booking", "destroy", gone.id ] ].sort,
      versions.map { [ it.item_type, it.event, it.item_id ] }.sort
    assert versions.all? { it.whodunnit == "airbnb" && it.place_id == places(:tomo).id && it.room_id == rooms(:garden).id }

    assert_no_difference(-> { PaperTrail::Version.count }) { assert @feed.sync }
  end

  test "the same sync error twice logs once; recovery logs once" do
    stub_feed(body: "", status: 404)
    assert_difference(-> { @feed.versions.count }, 1) { assert_not @feed.sync }
    assert_equal [ nil, "RuntimeError: HTTP 404" ], @feed.versions.last.object_changes["last_error"]

    travel 2.minutes
    assert_no_difference(-> { @feed.versions.count }) { assert_not @feed.sync }

    stub_feed("airbnb.ics")
    assert_difference(-> { @feed.versions.count }, 1) { assert @feed.sync }
    assert_equal [ "RuntimeError: HTTP 404", nil ], @feed.versions.last.object_changes["last_error"]
    assert_equal "airbnb", @feed.versions.last.whodunnit
  end

  test "sync from an admin request logs the provider and restores the user afterwards" do
    stub_feed("airbnb.ics")
    PaperTrail.request(whodunnit: users(:owner).id.to_s) do
      assert @feed.sync
      assert_equal users(:owner).id.to_s, PaperTrail.request.whodunnit
    end
    assert_equal [ "airbnb" ], PaperTrail::Version.where(item_type: "Booking").distinct.pluck(:whodunnit)
  end

  test "no version stores the feed URL" do
    stub_feed(body: "", status: 404)
    @feed.sync
    stub_feed("airbnb.ics")
    @feed.sync
    @feed.destroy!
    PaperTrail::Version.find_each do |version|
      assert_not_includes version.attributes.to_json, "s=token"
    end
  end

  test "a checked-in stay missing from the feed is kept and flagged, and unflagged when it returns" do
    in_house = ical_booking("1418fb94e984-reserved-1@airbnb.com", "2026-10-04", "2026-10-07")
    in_house.update_columns(checked_in_at: 1.day.ago)
    checked_out = ical_booking("left@airbnb.com", "2026-10-04", "2026-10-08")
    checked_out.update_columns(checked_in_at: 1.day.ago, checked_out_at: 1.hour.ago)
    waiting = ical_booking("waiting@airbnb.com", "2026-10-09", "2026-10-10")
    stub_feed("empty.ics")

    assert @feed.sync
    assert_equal Time.current, in_house.reload.removed_from_feed_at
    assert in_house.confirmed?
    assert checked_out.reload.removed_from_feed_at
    assert_not Booking.exists?(waiting.id)
    assert_equal "OTA đã huỷ, khách đang ở",
      ApplicationController.helpers.activity_entry(in_house.versions.reorder(:id).last)[:action]

    travel 1.hour
    assert @feed.sync
    assert_equal Time.current - 1.hour, in_house.reload.removed_from_feed_at, "flagged once"

    stub_feed("airbnb.ics")
    assert @feed.sync
    assert_nil in_house.reload.removed_from_feed_at
  end
end
