require "test_helper"

# Kênh bán phòng in the PWA (#246): list and sync for the desk, links and commissions for owners.
class Pms::ChannelsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  URL = "https://1.1.1.1/calendar/ical/42.ics?s=secret-token"

  setup do
    travel_to Time.zone.local(2026, 10, 5, 12)
    @feed = rooms(:limdim).calendar_feeds.create!(url: "https://1.1.1.1/limdim.ics?t=other-token", provider: "booking") # IP literal: no DNS
    @other_room = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    @other_feed = @other_room.calendar_feeds.create!(url: "https://1.1.1.1/other.ics", provider: "booking")
  end

  def staff!
    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    log_in staff
  end

  test "lists channels with status, failing link's message and last success; never the URL or raw error" do
    @feed.update_columns(last_error: "RuntimeError: HTTP 404", last_error_at: 1.hour.ago, last_synced_at: 1.day.ago)
    calendar_feeds(:limdim_airbnb).update_columns(last_synced_at: 2.hours.ago)
    places(:tomo).update!(commissions: { "booking" => 15 })
    @feed.sync_runs.create!(trigger: "hourly", ok: false, error: "RuntimeError: HTTP 404", started_at: 1.hour.ago, finished_at: 1.hour.ago)
    log_in users(:owner)

    get pms_more_path
    assert_select "main a[href=?]", pms_channels_path, text: /Kênh bán phòng/
    get pms_channels_path
    assert_response :success
    assert_select "header", text: /1 link lỗi · tự đồng bộ mỗi giờ · tomo homestay/
    assert_select "#channel_booking", text: /Booking.com\s*1 phòng · 0 đặt phòng tháng này · hoa hồng 15%\s*Lỗi/
    assert_select "#channel_airbnb", text: /Airbnb.*Đang chạy/m
    assert_select "#channel_agoda", text: /Chưa nhập link lịch\s*Chưa kết nối/
    assert_select "##{dom_id(@feed)}", text: /Phòng Limdim\s*1\.1\.1\.1.*Lỗi hôm nay 11:00 · thành công lần cuối hôm qua 12:00.*Link iCal không còn dùng được/m
    assert_select "##{dom_id(@feed)} form[action=?]", sync_pms_calendar_feed_path(@feed), 0 # gone: a new link is the fix
    assert_select "#sync_log", text: /Booking.com phòng Limdim: link iCal không còn dùng được/
    assert_select "#channel_agoda_sheet form[action=?] select[name=room_id] option", pms_calendar_feeds_path, 2
    assert_select "#channel_booking_sheet select[name=room_id] option", text: "Phòng Garden"
    assert_select "body", text: /Đồi/, count: 0
    assert_no_match "token", response.body
    assert_no_match "HTTP 404", response.body
  end

  test "owner connects a link: it syncs straight away" do
    stub_request(:get, URL).to_return(body: file_fixture("airbnb.ics").read)
    log_in users(:owner)
    assert_difference -> { rooms(:garden).calendar_feeds.count }, 1 do
      post pms_calendar_feeds_path, params: { room_id: rooms(:garden).id, calendar_feed: { provider: "agoda", url: URL } }
    end
    feed = rooms(:garden).calendar_feeds.sole
    assert_equal [ "agoda", 2, "added" ], [ feed.provider, feed.bookings.count, feed.sync_runs.sole.trigger ]
    assert_redirected_to pms_channels_path
    follow_redirect!
    assert_select ".pms-toast", text: "Agoda đã đọc được lịch phòng Garden"
    assert_select "#channel_agoda", text: /Đang chạy/
  end

  test "a link that fails to sync is kept with its error; an invalid one is refused without echoing it" do
    stub_request(:get, URL).to_return(status: 500)
    log_in users(:owner)
    post pms_calendar_feeds_path, params: { room_id: rooms(:garden).id, calendar_feed: { provider: "agoda", url: URL } }
    follow_redirect!
    assert_select "[role=alert]", text: "Đã kết nối phòng Garden, nhưng đồng bộ lỗi. Không tải được lịch lúc này. hueni tự thử lại mỗi giờ."

    assert_no_difference -> { CalendarFeed.count } do
      post pms_calendar_feeds_path, params: { room_id: rooms(:garden).id, calendar_feed: { provider: "agoda", url: "http://127.0.0.1/x.ics" } }
    end
    follow_redirect!
    assert_select "[role=alert]", text: /Link iCal/
    assert_no_match "127.0.0.1", response.body
  end

  test "sync one link, limited to once a minute; owner removes a link and its bookings" do
    stub_request(:get, @feed.url).to_return(body: file_fixture("airbnb.ics").read)
    log_in users(:owner)
    post sync_pms_calendar_feed_path(@feed)
    follow_redirect!
    assert_select ".pms-toast", text: "Đã đồng bộ Booking.com phòng Limdim"
    assert_equal 2, @feed.bookings.count

    post sync_pms_calendar_feed_path(@feed)
    assert_equal "Vừa đồng bộ, thử lại sau 1 phút.", flash[:alert]
    assert_requested :get, @feed.url, times: 1

    assert_difference -> { Booking.count }, -2 do
      delete pms_calendar_feed_path(@feed)
    end
    follow_redirect!
    assert_select ".pms-toast", text: /Đã ngắt Booking.com phòng Limdim/
  end

  test "Đồng bộ tất cả queues the links not synced in the last minute" do
    calendar_feeds(:limdim_airbnb).update_columns(last_synced_at: 30.seconds.ago)
    staff!
    assert_enqueued_jobs 1, only: SyncCalendarFeedJob do
      post pms_channels_sync_path
    end
    assert_enqueued_with job: SyncCalendarFeedJob, args: [ @feed.id, "manual" ]
    follow_redirect!
    assert_select ".pms-toast", text: "Đang đồng bộ 1 link. Tải lại trang sau ít phút."
  end

  test "owner sets one OTA's commission, the others stay; Báo cáo uses it" do
    places(:tomo).update!(commissions: { "airbnb" => 3 })
    log_in users(:owner)
    patch pms_channels_commissions_path, params: { place: { commissions: { booking: "15,5" } } }
    follow_redirect!
    assert_select ".pms-toast", text: "Đã lưu hoa hồng"
    assert_equal({ "airbnb" => 3.0, "booking" => 15.5 }, places(:tomo).reload.commissions)
    assert_select "input[name='place[commissions][booking]'][value='15,5']"

    patch pms_channels_commissions_path, params: { place: { commissions: { booking: "120" } } }
    follow_redirect!
    assert_select "[role=alert]", text: "Hoa hồng phải là số từ 0 đến 100."

    patch pms_channels_commissions_path, params: { place: { commissions: { airbnb: "" } } }
    assert_equal({ "booking" => 15.5 }, places(:tomo).reload.commissions)
  end

  test "staff sees and syncs, but can't connect, remove or set commissions" do
    stub_request(:get, @feed.url).to_return(body: file_fixture("airbnb.ics").read)
    staff!
    get pms_channels_path
    assert_response :success
    assert_select "form[action=?]", sync_pms_calendar_feed_path(@feed)
    assert_select "form[action=?]", pms_calendar_feeds_path, 0
    assert_select "form[action=?]", pms_channels_commissions_path, 0
    assert_select "form[action=?]", pms_calendar_feed_path(@feed), 0
    post sync_pms_calendar_feed_path(@feed)
    assert_redirected_to pms_channels_path

    post pms_calendar_feeds_path, params: { room_id: rooms(:garden).id, calendar_feed: { provider: "agoda", url: URL } }
    assert_response :forbidden
    delete pms_calendar_feed_path(@feed)
    assert_response :forbidden
    patch pms_channels_commissions_path, params: { place: { commissions: { booking: "1" } } }
    assert_response :forbidden
    assert CalendarFeed.exists?(@feed.id)
    assert_empty places(:tomo).reload.commissions
  end

  test "another owner's room and links are not found" do
    log_in users(:owner)
    post pms_calendar_feeds_path, params: { room_id: @other_room.id, calendar_feed: { provider: "agoda", url: URL } }
    assert_response :not_found
    post sync_pms_calendar_feed_path(@other_feed)
    assert_response :not_found
    delete pms_calendar_feed_path(@other_feed)
    assert_response :not_found
    assert CalendarFeed.exists?(@other_feed.id)
    assert_not_requested :get, @other_feed.url
  end
end
