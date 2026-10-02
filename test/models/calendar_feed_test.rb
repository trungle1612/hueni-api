require "test_helper"

class CalendarFeedTest < ActiveSupport::TestCase
  def feed(url) = CalendarFeed.new(room: rooms(:garden), url:, provider: "other")

  test "accepts http(s) urls on public addresses" do
    assert feed("https://1.1.1.1/calendar.ics").valid?
    assert feed("http://1.1.1.1/calendar.ics").valid?
  end

  test "rejects non-http schemes" do
    %w[file:///etc/passwd ftp://1.1.1.1/a.ics javascript:alert(1)].each do |url|
      assert_not feed(url).valid?, url
    end
  end

  test "rejects hosts resolving to private, loopback, link-local or unspecified addresses" do
    %w[
      http://127.0.0.1/a.ics http://localhost/a.ics http://10.0.0.1/a.ics http://172.16.0.1/a.ics
      http://192.168.1.1/a.ics http://169.254.169.254/latest/meta-data http://0.0.0.0/a.ics
      http://[::1]/a.ics http://[fd00::1]/a.ics http://[fe80::1]/a.ics
    ].each do |url|
      assert_not feed(url).valid?, url
    end
  end

  test "rejects blank, malformed and unresolvable urls" do
    [ nil, "", "not a url", "https://", "https://does-not-exist.invalid/a.ics" ].each do |url|
      assert_not feed(url).valid?, url.inspect
    end
  end

  test "provider must be known" do
    assert_not CalendarFeed.new(room: rooms(:garden), url: "https://1.1.1.1/a.ics", provider: "expedia").valid?
  end

  test "url is unique per room" do
    dup = CalendarFeed.new(room: rooms(:limdim), url: calendar_feeds(:limdim_airbnb).url, provider: "airbnb")
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }

    feed = CalendarFeed.create!(room: rooms(:garden), url: "https://1.1.1.1/a.ics", provider: "airbnb")
    assert_not CalendarFeed.new(room: rooms(:garden), url: feed.url, provider: "airbnb").valid?
    assert CalendarFeed.new(room: rooms(:limdim), url: feed.url, provider: "airbnb").valid?
  end

  test "synced_recently? looks at the last success or failure" do
    travel_to Time.zone.local(2026, 10, 5, 12)
    feed = calendar_feeds(:limdim_airbnb)
    assert_not feed.synced_recently?
    feed.last_synced_at = 30.seconds.ago
    assert feed.synced_recently?
    feed.last_synced_at = 2.minutes.ago
    assert_not feed.synced_recently?
    feed.last_error_at = 10.seconds.ago
    assert feed.synced_recently?
  end

  test "provider label and link host" do
    feed = calendar_feeds(:limdim_airbnb)
    assert_equal [ "Airbnb", "www.airbnb.com" ], [ feed.provider_label, feed.url_host ]
    assert_equal "Booking.com", CalendarFeed.new(provider: "booking").provider_label
  end

  test "deleting a feed deletes its bookings" do
    feed = calendar_feeds(:limdim_airbnb)
    feed.bookings.create!(room: feed.room, start_date: "2026-11-01", end_date: "2026-11-03", source: "ical", uid: "a@airbnb")
    assert_difference -> { Booking.count }, -1 do
      feed.destroy!
    end
  end

  test "bookings reference an existing feed" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Booking.new(room: rooms(:garden), start_date: "2026-11-01", end_date: "2026-11-02", calendar_feed_id: 0).save(validate: false)
    end
  end
end
