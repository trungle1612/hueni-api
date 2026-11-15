require "test_helper"

# Báo cáo in the PWA (#234): the same Report as /admin for the current homestay.
class Pms::ReportTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 12)
    rooms(:limdim).update!(price: 400_000)
  end

  def staff!(permissions: [])
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff", permissions:)
    log_in users(:admin)
  end

  test "owner sees this month with the numbers of /admin, the weekly chart and a debt" do
    rooms(:limdim).bookings.create!(start_date: "2026-10-09", end_date: "2026-10-12", guest_name: "Chị Mai", price: 900_000)
    rooms(:limdim).bookings.create!(start_date: "2026-10-25", end_date: "2026-10-27")
    log_in users(:owner)
    get pms_report_path

    assert_response :success
    assert_select "header", text: /Báo cáo\s*1 – 20\/10\/2026 · tomo homestay/
    assert_select "nav[aria-label='Điều hướng chính'] a[aria-current=page]", text: "Báo cáo"
    assert_select "#periods a[aria-current=page]", "Tháng này"
    assert_select "#month", "Tháng 10/2026"
    report = Report.new(places(:tomo), Date.current)
    assert_select "#kpi-revenue dd", text: "#{ActiveSupport::NumberHelper.number_to_delimited(report.revenue, delimiter: ".")}đ"
    assert_select "#kpi-occupancy dd", text: "#{(report.occupancy * 100).round}%"
    assert_select "#kpi-due dd", text: "#{ActiveSupport::NumberHelper.number_to_delimited(report.due, delimiter: ".")}đ"
    assert_select "#ahead", /Đã đặt trước 2 đêm từ 21\/10/
    assert_select "#chart h2", text: /8–14 cao nhất tháng/
    assert_select "#chart input[type=radio]", 3                       # 1–7, 8–14, 15–20
    assert_select "#chart input[checked][aria-label=?]", "8–14: 2,7 triệu"
    assert_select "#debts a[href=?]", pms_booking_path(Booking.find_by!(guest_name: "Chị Mai")), text: /Chị Mai.*Quá hạn 8 ngày · trả phòng 12\/10/m
    assert_select "#rooms tr", text: /Limdim/
    assert_select "#channels", text: /Trực tiếp/
    assert_select "#bookings", text: /Đã xác nhận\s*2/
    assert_select "a[href=?]", pms_report_path(month: "2026-09"), text: "‹ Tháng 9"
    assert_select "a#csv[href=?]", pms_report_path(format: :csv, month: "2026-10")
  end

  test "7 ngày charts by day, an empty month says so, Xuất CSV downloads the same file as /admin" do
    rooms(:limdim).bookings.create!(start_date: "2026-10-18", end_date: "2026-10-19")
    log_in users(:owner)
    get pms_report_path(period: "7d")
    assert_select "#periods a[aria-current=page]", "7 ngày"
    assert_select "#chart input[type=radio]", 7
    assert_select "#chart .l", text: "T3"                             # 20/10/2026 is a Tuesday
    assert_select "#chart input[checked][aria-label=?]", "CN: 0,4 triệu"

    get pms_report_path(month: "2025-01")
    assert_select "#empty", /Tháng 1 không có đêm nào có khách/
    assert_select "#kpis, #chart", 0

    get pms_report_path(month: "nope")
    assert_select "#month", "Tháng 10/2026"

    get pms_report_path(period: "7d", format: :csv)
    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=utf-8"
    assert_match "bao-cao-tomo-homestay-2026-10-14-2026-10-20.csv", response.headers["Content-Disposition"]
    assert_equal Report.week(places(:tomo)).to_csv, response.body.force_encoding("UTF-8")
  end

  test "staff without the report right get 403, with it they see the report" do
    staff!
    get pms_report_path
    assert_response :forbidden
    get pms_report_path(format: :csv)
    assert_response :forbidden

    places(:tomo).place_memberships.find_by!(user: users(:admin)).update!(permissions: [ "report" ])
    get pms_report_path
    assert_response :success
    assert_select "#kpi-revenue"
  end

  test "a user with no homestay sees no other homestay's report" do
    user = User.create!(name: "Người lạ", phone_number: "0911000111", password: "password123", role: "admin")
    log_in user
    get pms_report_path
    assert_response :success
    assert_select "#kpis", 0
    assert_select "main", text: /Bạn chưa thuộc cơ sở nào/
  end
end
