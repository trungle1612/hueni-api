require "test_helper"

class Admin::ActivitiesControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { phone_number: user.phone_number, password: "password123" }
  end

  def staff
    @staff ||= User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123").tap do
      it.place_memberships.create!(place: places(:tomo), role: "staff")
    end
  end

  setup { travel_to Time.zone.local(2026, 10, 5, 14, 5) }

  test "owner sees the homestay's activity, newest first, two lines per change" do
    PaperTrail.request(whodunnit: staff.id.to_s) do
      rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07", status: "hold", guest_name: "Chị Mai")
    end
    PaperTrail.request(whodunnit: "airbnb") do
      calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:limdim), uid: "a", start_date: "2026-10-12", end_date: "2026-10-14", source: "ical")
    end
    places(:hiuhill).rooms.create!(name: "Không phải của tôi", max_guests: 1)

    log_in users(:owner)
    get admin_place_activity_path("tomo-homestay")

    assert_response :success
    assert_select "h1", "Hoạt động"
    assert_select "h3", "Hôm nay"
    rows = css_select("[id^=version_]")
    assert_equal 2, rows.size
    assert_equal "Phòng Limdim Đặt phòng · 12/10–14/10 Airbnb 14:05", rows[0].text.squish
    assert_equal "Phòng Garden Giữ chỗ · Chị Mai 05/10–07/10 Em Hằng 14:05", rows[1].text.squish
    assert_no_match "Không phải của tôi", response.body
    assert_select "a", text: "Xem cũ hơn", count: 0
  end

  test "staff gets 403; another owner's homestay and an admin without membership get 404" do
    log_in users(:admin)
    get admin_place_activity_path("tomo-homestay")
    assert_response :not_found

    log_in staff
    get admin_place_activity_path("tomo-homestay")
    assert_response :forbidden

    log_in users(:owner)
    get admin_place_activity_path("hiuhill-homestay")
    assert_response :not_found
  end

  test "50 per page with Xem cũ hơn; a bad cursor doesn't break the page" do
    51.times { |i| rooms(:garden).update!(max_guests: i + 3) }
    log_in users(:owner)

    get admin_place_activity_path("tomo-homestay")
    assert_select "[id^=version_]", 50
    oldest_shown = PaperTrail::Version.order(:id).second
    assert_select "a[href=?]", admin_place_activity_path("tomo-homestay", before: oldest_shown.id), text: "Xem cũ hơn"

    get admin_place_activity_path("tomo-homestay", before: oldest_shown.id)
    assert_select "[id^=version_]", 1
    assert_select "a", text: "Xem cũ hơn", count: 0

    get admin_place_activity_path("tomo-homestay", before: "abc")
    assert_select "[id^=version_]", 50
    get admin_place_activity_path("tomo-homestay", before: [ 1 ])
    assert_select "[id^=version_]", 50
    get admin_place_activity_path("tomo-homestay", before: "")
    assert_select "[id^=version_]", 50
  end

  test "the feed URL never shows; sync errors do" do
    feed = rooms(:garden).calendar_feeds.create!(url: "https://1.1.1.1/x.ics?s=secret-token", provider: "booking")
    stub_request(:get, feed.url).to_return(status: 404)
    feed.sync

    log_in users(:owner)
    get admin_place_activity_path("tomo-homestay")
    rows = css_select("[id^=version_]").map { it.text.squish }
    assert_equal [ "Phòng Garden Đồng bộ lỗi · RuntimeError: HTTP 404 Booking.com 14:05",
      "Phòng Garden Thêm kênh · Booking.com Hệ thống 14:05" ], rows
    assert_no_match "secret-token", response.body
  end

  test "Hoạt động button on the homestay page for owners only" do
    log_in users(:owner)
    get admin_place_path("tomo-homestay")
    assert_select "a[href=?]", admin_place_activity_path("tomo-homestay"), text: "Hoạt động"

    log_in staff
    get admin_place_path("tomo-homestay")
    assert_select "a[href=?]", admin_place_activity_path("tomo-homestay"), count: 0
  end

  test "booking edit shows the booking's history to owners, not to staff" do
    booking = bookings(:limdim_confirmed)
    PaperTrail.request(whodunnit: users(:owner).id.to_s) { booking.update!(note: "Đến muộn") }

    log_in users(:owner)
    get edit_admin_booking_path(booking)
    assert_select "#history h2", "Lịch sử"
    assert_equal "Sửa đặt phòng · Anh Minh: sửa ghi chú Chị Lan 14:05", css_select("#history [id^=version_]").first.text.squish

    log_in staff
    get edit_admin_booking_path(booking)
    assert_response :success
    assert_select "#history", 0
  end

  test "room edit shows the last 20 changes of the room, its bookings and feeds" do
    PaperTrail.request(whodunnit: users(:owner).id.to_s) do
      rooms(:garden).update!(price: 350_000)
      rooms(:garden).bookings.create!(start_date: "2026-10-06", end_date: "2026-10-07", guest_name: "Chị Mai")
      rooms(:limdim).update!(price: 1)
    end

    log_in users(:owner)
    get edit_admin_room_path(rooms(:garden))
    assert_select "#history [id^=version_]", 2
    assert_select "#history", text: /giá chưa có → 350.000 ₫/
    assert_select "#history", text: /Đặt phòng · Chị Mai 06\/10–07\/10/
    assert_select "#history", text: /Phòng Garden/, count: 0
    assert_select "#history a[href=?]", admin_place_activity_path("tomo-homestay"), text: /Xem tất cả hoạt động/

    21.times { |i| rooms(:garden).update!(max_guests: i + 3) }
    get edit_admin_room_path(rooms(:garden))
    assert_select "#history [id^=version_]", 20
  end
end
