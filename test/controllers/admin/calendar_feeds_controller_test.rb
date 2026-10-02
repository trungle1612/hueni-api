require "test_helper"

class Admin::CalendarFeedsControllerTest < ActionDispatch::IntegrationTest
  URL = "https://1.1.1.1/calendar/ical/42.ics?s=secret-token"

  def log_in(user)
    post session_path, params: { phone_number: user.phone_number, password: "password123" }
  end

  setup do
    log_in users(:owner)
    travel_to Time.zone.local(2026, 10, 5, 12)
    @other_room = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    @other_feed = @other_room.calendar_feeds.create!(url: "https://1.1.1.1/other.ics", provider: "booking")
    @feed = rooms(:limdim).calendar_feeds.create!(url: "https://1.1.1.1/limdim.ics", provider: "booking") # IP literal: no DNS
  end

  test "adding a feed syncs it right away" do
    stub_request(:get, URL).to_return(body: file_fixture("airbnb.ics").read)

    assert_difference -> { rooms(:garden).calendar_feeds.count }, 1 do
      post admin_room_calendar_feeds_path(rooms(:garden)), params: { calendar_feed: { provider: "airbnb", url: URL, room_id: @other_room.id } }
    end
    feed = rooms(:garden).calendar_feeds.last
    assert_equal 2, feed.bookings.count
    assert_equal Time.current, feed.last_synced_at
    assert_redirected_to edit_admin_room_path(rooms(:garden))
    follow_redirect!
    assert_select "[role=alert]", text: /Đã thêm và đồng bộ/
  end

  test "added feed that fails to sync is kept with its error" do
    stub_request(:get, URL).to_return(status: 404)
    post admin_room_calendar_feeds_path(rooms(:garden)), params: { calendar_feed: { provider: "airbnb", url: URL } }
    follow_redirect!
    assert_select "[role=alert]", text: /đồng bộ lỗi: .*HTTP 404/
    assert_match "HTTP 404", rooms(:garden).calendar_feeds.last.last_error
  end

  test "private, malformed or duplicate links are rejected" do
    [ "http://127.0.0.1/x.ics", "nope", @feed.url ].each do |url|
      assert_no_difference -> { CalendarFeed.count } do
        post admin_room_calendar_feeds_path(rooms(:limdim)), params: { calendar_feed: { provider: "airbnb", url: } }
      end
      assert_response :unprocessable_entity
      assert_select "[role=alert]", text: /Link iCal/
    end
  end

  test "sync now reports success, then is limited to once a minute" do
    feed = @feed
    stub_request(:get, feed.url).to_return(body: file_fixture("airbnb.ics").read)

    post sync_admin_calendar_feed_path(feed)
    assert_redirected_to edit_admin_room_path(rooms(:limdim))
    assert_equal "Đã đồng bộ.", flash[:notice]

    travel 30.seconds
    post sync_admin_calendar_feed_path(feed)
    assert_equal "Vừa đồng bộ, thử lại sau 1 phút.", flash[:alert]
    assert_requested :get, feed.url, times: 1

    travel 31.seconds
    post sync_admin_calendar_feed_path(feed)
    assert_requested :get, feed.url, times: 2
  end

  test "sync now shows the error" do
    feed = @feed
    stub_request(:get, feed.url).to_return(status: 500)
    post sync_admin_calendar_feed_path(feed)
    assert_match "HTTP 500", flash[:alert]
  end

  test "deleting a feed removes its bookings" do
    feed = @feed
    feed.bookings.create!(room: rooms(:limdim), uid: "a", start_date: "2026-10-10", end_date: "2026-10-12", source: "ical")
    assert_difference -> { Booking.count }, -1 do
      delete admin_calendar_feed_path(feed)
    end
    assert_not CalendarFeed.exists?(feed.id)
    assert_redirected_to edit_admin_room_path(rooms(:limdim))
  end

  test "another owner's room and feeds are not found" do
    post admin_room_calendar_feeds_path(@other_room), params: { calendar_feed: { provider: "airbnb", url: URL } }
    assert_response :not_found
    post sync_admin_calendar_feed_path(@other_feed)
    assert_response :not_found
    delete admin_calendar_feed_path(@other_feed)
    assert_response :not_found
    assert CalendarFeed.exists?(@other_feed.id)
    assert_not_requested :get, @other_feed.url
  end

  test "room page lists feeds without leaking the token" do
    calendar_feeds(:limdim_airbnb).update_columns(last_error: "RuntimeError: HTTP 404", last_error_at: 2.hours.ago)
    get edit_admin_room_path(rooms(:limdim))
    assert_select "#calendar_feed_#{calendar_feeds(:limdim_airbnb).id}", text: /Airbnb.*www\.airbnb\.com.*HTTP 404/m
    assert_no_match "secret-token", response.body
  end

  test "overview lists own rooms by homestay, rooms with errors first" do
    @feed.update_columns(last_error: "boom", last_error_at: 1.hour.ago)
    get admin_calendar_feeds_path
    assert_response :success
    assert_select "[data-room]" do |rows|
      assert_equal [ rooms(:limdim).id, rooms(:garden).id ].map(&:to_s), rows.map { it["data-room"] }
    end
    assert_select "a[href=?]", edit_admin_room_path(rooms(:limdim))
    assert_select "body", text: /Đồi/, count: 0
    assert_select "aside a.menu-active", text: /Kênh OTA/
    assert_no_match "secret-token", response.body
  end
end
