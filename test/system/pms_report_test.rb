require "application_system_test_case"

class PmsReportTest < ApplicationSystemTestCase
  test "owner opens Báo cáo, picks 7 ngày and taps a bar to see its revenue" do
    travel_to Time.zone.local(2026, 10, 20, 9)
    rooms(:limdim).update!(price: 400_000)
    rooms(:limdim).bookings.create!(start_date: "2026-10-16", end_date: "2026-10-17", guest_name: "Chị Mai", price: 900_000)
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    within("nav[aria-label='Điều hướng chính']") { click_link "Báo cáo" }
    assert_selector "h1", text: "Báo cáo"
    assert_selector "#month", text: "Tháng 10/2026"

    click_link "7 ngày"
    assert_selector "#periods a[aria-current=page]", text: "7 ngày"
    assert_selector "#chart h2", text: "T6 cao nhất tuần"
    assert_selector "#chart .pms-bcol .v", text: "0,9", visible: true
    assert_no_selector "#chart .pms-bcol .v", text: "0", exact_text: true, visible: true
    find("#chart .pms-bcol", text: "T2").click
    assert_selector "#chart .pms-bcol .v", text: "0", exact_text: true, visible: true
    assert_no_selector "#chart .pms-bcol .v", text: "0,9", visible: true
  end
end
