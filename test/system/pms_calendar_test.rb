require "application_system_test_case"

class PmsCalendarTest < ApplicationSystemTestCase
  test "owner opens Lịch, peeks at a booking, goes to next week and books a free cell" do
    travel_to Time.zone.local(2026, 10, 2, 9)
    booking = bookings(:limdim_confirmed) # 1/10–3/10, Anh Minh
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"
    within("nav[aria-label='Điều hướng chính']") { click_link "Lịch" }

    assert_selector "h1", text: "Lịch phòng"
    click_button "! Anh Minh"
    within("#peek_booking_#{booking.id}") do
      assert_text "Chưa cọc"
      assert_text "Phòng Limdim · 01 – 03/10 · 2 đêm"
      click_button "Đóng"
    end
    assert_no_selector "#peek_booking_#{booking.id}", visible: true

    # A tap outside an open sheet only closes it, it doesn't also follow what's under the scrim.
    click_button "! Anh Minh"
    assert_selector "#peek_booking_#{booking.id}", visible: true
    find("a[aria-label='Tuần sau']").click
    assert_no_selector "#peek_booking_#{booking.id}", visible: true
    assert_no_text "09/10 – 15/10/2026"

    # Tapping the same bar again closes its sheet.
    click_button "! Anh Minh"
    assert_selector "#peek_booking_#{booking.id}", visible: true
    click_button "! Anh Minh"
    assert_no_selector "#peek_booking_#{booking.id}", visible: true

    find("a[aria-label='Tuần sau']").click
    assert_text "09/10 – 15/10/2026"
    find("a[aria-label='Phòng Garden, 10/10, trống. Đặt phòng']").click
    assert_field "booking[start_date]", with: "2026-10-10"
  end
end
