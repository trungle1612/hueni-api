require "test_helper"

class Admin::ReportsControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { phone_number: user.phone_number, password: "password123" }
  end

  def staff
    @staff ||= User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123").tap do
      it.place_memberships.create!(place: places(:tomo), role: "staff")
    end
  end

  setup do
    travel_to Time.zone.local(2026, 10, 20, 12)
    rooms(:limdim).update!(price: 400_000)
  end

  test "owner sees the month's report with tiles, rooms, channels and bookings" do
    log_in users(:owner)
    get admin_place_report_path("tomo-homestay")

    assert_response :success
    assert_select "h1", "Báo cáo"
    assert_select "#month", "Tháng 10/2026"
    assert_select "#tile-occupancy", /3%/            # 2 / 62
    assert_select "#tile-revenue", /800\.000 ₫/
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

  test "an empty month shows dashes, not errors" do
    log_in users(:owner)
    get admin_place_report_path("tomo-homestay", month: "2025-01")
    assert_response :success
    assert_select "#tile-adr", /—/
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
