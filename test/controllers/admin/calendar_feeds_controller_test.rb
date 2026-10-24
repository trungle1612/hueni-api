require "test_helper"

class Admin::CalendarFeedsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  URL = "https://1.1.1.1/calendar/ical/42.ics?s=secret-token"

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
    assert_equal "added", feed.sync_runs.sole.trigger
    assert_redirected_to edit_admin_room_path(rooms(:garden))
    follow_redirect!
    assert_select "[role=alert]", text: /Đã thêm và đồng bộ/
  end

  test "added feed that fails to sync is kept with its error" do
    stub_request(:get, URL).to_return(status: 404)
    post admin_room_calendar_feeds_path(rooms(:garden)), params: { calendar_feed: { provider: "airbnb", url: URL } }
    follow_redirect!
    assert_select "[role=alert]", text: "Đã thêm, nhưng đồng bộ lỗi. Link iCal không còn dùng được. Lấy link mới trên Airbnb / Booking.com rồi thêm lại kênh."
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
    assert_redirected_to admin_calendar_feeds_path
    assert_equal "Đã đồng bộ.", flash[:notice]
    assert_equal "manual", feed.sync_runs.sole.trigger

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
    assert_equal "Đồng bộ lỗi. Không tải được lịch lúc này. hueni tự thử lại mỗi giờ.", flash[:alert]
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

  test "room page lists feeds without leaking the token; owners get the error in words, admins also raw" do
    calendar_feeds(:limdim_airbnb).update_columns(last_error: "RuntimeError: HTTP 404", last_error_at: 2.hours.ago)
    get edit_admin_room_path(rooms(:limdim))
    assert_select "#calendar_feed_#{calendar_feeds(:limdim_airbnb).id}", text: /Airbnb.*www\.airbnb\.com.*Link iCal không còn dùng được/m
    assert_no_match "HTTP 404", response.body
    assert_no_match "secret-token", response.body

    users(:admin).place_memberships.create!(place: places(:tomo), role: "owner")
    delete session_path
    log_in users(:admin)
    get edit_admin_room_path(rooms(:limdim))
    assert_select "#calendar_feed_#{calendar_feeds(:limdim_airbnb).id} .font-mono", "RuntimeError: HTTP 404"
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

  test "staff can sync from the overview but can't add or delete feeds" do
    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    delete session_path
    log_in staff
    stub_request(:get, @feed.url).to_return(body: file_fixture("airbnb.ics").read)

    post sync_admin_calendar_feed_path(@feed), headers: { "Referer" => admin_calendar_feeds_url }
    assert_redirected_to admin_calendar_feeds_url
    assert_equal "Đã đồng bộ.", flash[:notice]

    post admin_room_calendar_feeds_path(rooms(:garden)), params: { calendar_feed: { provider: "airbnb", url: URL } }
    assert_response :forbidden
    delete admin_calendar_feed_path(@feed)
    assert_response :forbidden
    assert CalendarFeed.exists?(@feed.id)
  end

  test "overview: everyone gets sync buttons, only owners get links to the room page" do
    get admin_calendar_feeds_path
    assert_select "form[action=?] button", sync_admin_calendar_feed_path(@feed)
    assert_select "a[href=?]", edit_admin_room_path(rooms(:limdim))

    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    delete session_path
    log_in staff
    get admin_calendar_feeds_path
    assert_select "form[action=?] button", sync_admin_calendar_feed_path(@feed)
    assert_select "a[href=?]", edit_admin_room_path(rooms(:limdim)), 0
  end

  test "Đồng bộ tất cả queues every feed of the homestay not synced in the last minute; staff too" do
    calendar_feeds(:limdim_airbnb).update_columns(last_synced_at: 30.seconds.ago)
    garden = rooms(:garden).calendar_feeds.create!(url: "https://1.1.1.1/garden.ics", provider: "agoda")
    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    delete session_path
    log_in staff

    get admin_calendar_feeds_path
    assert_select "#tomo-homestay form[action=?] button", sync_feeds_admin_place_path("tomo-homestay"), text: "↻ Đồng bộ tất cả"
    assert_select "[id^=commissions_place_]", 0 # owners only

    assert_enqueued_jobs 2, only: SyncCalendarFeedJob do
      post sync_feeds_admin_place_path("tomo-homestay")
    end
    assert_enqueued_with job: SyncCalendarFeedJob, args: [ @feed.id, "manual" ]
    assert_enqueued_with job: SyncCalendarFeedJob, args: [ garden.id, "manual" ]
    assert_equal "Đang đồng bộ 2 kênh của tomo homestay. Tải lại trang sau ít phút.", flash[:notice]

    post sync_feeds_admin_place_path("hiuhill-homestay")
    assert_response :not_found
  end

  test "owners set the commission per OTA; staff can't" do
    get admin_calendar_feeds_path
    assert_select "#commissions_place_#{places(:tomo).id} summary", text: /Chưa nhập/

    patch commissions_admin_place_path("tomo-homestay"), params: { place: { commissions: { airbnb: "15,5", booking: " 18 ", agoda: "", other: "9" } } }
    assert_redirected_to admin_calendar_feeds_path(anchor: "tomo-homestay")
    assert_equal({ "airbnb" => 15.5, "booking" => 18.0 }, places(:tomo).reload.commissions)
    get admin_calendar_feeds_path
    assert_select "#commissions_place_#{places(:tomo).id} summary", text: /Airbnb 15,5% · Booking.com 18%/
    assert_select "input[name='place[commissions][airbnb]'][value='15,5']"

    patch commissions_admin_place_path("tomo-homestay"), params: { place: { commissions: { airbnb: "120", booking: "abc" } } }
    assert_equal "Hoa hồng phải là số từ 0 đến 100.", flash[:alert]
    assert_equal({ "airbnb" => 15.5, "booking" => 18.0 }, places(:tomo).reload.commissions)

    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    delete session_path
    log_in staff
    patch commissions_admin_place_path("tomo-homestay"), params: { place: { commissions: { airbnb: "1" } } }
    assert_response :forbidden
  end

  test "Agoda links can be added" do
    stub_request(:get, URL).to_return(body: file_fixture("airbnb.ics").read)
    post admin_room_calendar_feeds_path(rooms(:garden)), params: { calendar_feed: { provider: "agoda", url: URL } }
    assert_equal "Agoda", rooms(:garden).calendar_feeds.sole.provider_label
  end
end
