require "test_helper"

class Admin::ReportsControllerTest < ActionDispatch::IntegrationTest
  def staff
    @staff ||= User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123").tap do
      it.place_memberships.create!(place: places(:tomo), role: "staff")
    end
  end

  setup do
    travel_to Time.zone.local(2026, 10, 20, 12)
    rooms(:limdim).update!(price: 400_000)
  end

  test "owner sees the month so far in plain words: revenue first, rooms, channels, arrivals, booked ahead" do
    rooms(:limdim).bookings.create!(start_date: "2026-09-10", end_date: "2026-09-11")
    rooms(:limdim).bookings.create!(start_date: "2026-10-25", end_date: "2026-10-27")
    log_in users(:owner)
    get admin_place_report_path("tomo-homestay")

    assert_response :success
    assert_select "h1", "Báo cáo"
    assert_select "#month", "Tháng 10/2026"
    assert_select "nav", text: /đến hôm nay, 20\/10/
    assert_select "a", text: "Về tháng này", count: 0
    assert_select "#tile-revenue h2", "Tiền phòng 1–20/10 (ước tính)"
    assert_select "#tile-revenue", /800\.000 ₫\s*Từ 2 đêm có khách\.\s*tăng 100% so với 1–20\/9\./
    assert_select "#tile-revenue", /chưa trừ hoa hồng/
    assert_select "#ahead", /Đã đặt trước 2 đêm từ 21\/10 đến cuối tháng · khoảng 800\.000 ₫/
    assert_select "#tile-occupancy", /5%\s*2 trong 40 đêm tăng 3%/ # 2 / 40 vs 1 / 40
    assert_select "#tile-adr dt", "Giá trung bình mỗi đêm"
    assert_no_match(/RevPAR|ADR|ALOS|điểm|▲|▼/, response.body)
    assert_select "#rooms tr", text: /Limdim/
    assert_select "#rooms", text: /Chưa có giá/       # garden is unpriced
    assert_select "#channels", text: /Trực tiếp/
    assert_select "#bookings", text: /Đã xác nhận\s*1/
    assert_select "a[href=?]", admin_place_report_path("tomo-homestay", month: "2026-09")
    assert_select "a[href=?]", admin_place_report_path("tomo-homestay", month: "2026-11")
  end

  test "invalid month falls back to the current month" do
    log_in users(:owner)
    [ "2026-13", "abc", "" ].each do |month|
      get admin_place_report_path("tomo-homestay", month:)
      assert_response :success
      assert_select "#month", "Tháng 10/2026"
    end
    get admin_place_report_path("tomo-homestay"), params: { month: [ "x" ] }
    assert_response :success
  end

  test "an empty month says so in one line; a future month shows what is booked ahead, without comparison" do
    log_in users(:owner)
    get admin_place_report_path("tomo-homestay", month: "2025-01")
    assert_response :success
    assert_select "#empty", /Tháng 1 không có đêm nào có khách/
    assert_select "#tile-revenue, #stats, #rooms, #channels, #bookings", 0
    assert_select "a[href=?]", admin_place_report_path("tomo-homestay"), text: "Về tháng này"

    get admin_place_report_path("tomo-homestay", month: "2026-12")
    assert_select "#empty", /Chưa có ai đặt phòng cho tháng 12/

    rooms(:limdim).bookings.create!(start_date: "2026-11-02", end_date: "2026-11-05")
    get admin_place_report_path("tomo-homestay", month: "2026-11")
    assert_select "#tile-revenue h2", "Đã đặt trước cho tháng 11"
    assert_select "#tile-revenue", /3 đêm đã có khách đặt/
    assert_select ".badge", text: /tăng|giảm|bằng/, count: 0
    assert_select "#ahead", 0
  end

  test "staff gets 403; another owner's homestay and an admin without membership get 404" do
    log_in users(:admin)
    get admin_place_report_path("hiuhill-homestay")
    assert_response :not_found

    log_in staff
    get admin_place_report_path("tomo-homestay")
    assert_response :forbidden

    log_in users(:owner)
    get admin_place_report_path("hiuhill-homestay")
    assert_response :not_found
  end

  test "menu: owners get the item and land on their homestay; staff get neither" do
    log_in users(:owner)
    get admin_root_path
    assert_select "aside a", text: /Báo cáo/
    get admin_report_path
    assert_redirected_to admin_place_report_path("tomo-homestay")
    get admin_report_path(slug: "tomo-homestay", month: "2026-09")
    assert_redirected_to admin_place_report_path("tomo-homestay", month: "2026-09")
    get admin_report_path(slug: "hiuhill-homestay")
    assert_response :not_found

    log_in staff
    get admin_root_path
    assert_select "aside a", text: /Báo cáo/, count: 0
    get admin_report_path
    assert_redirected_to admin_root_path
  end
end
