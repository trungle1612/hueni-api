require "application_system_test_case"

class PmsSearchTest < ApplicationSystemTestCase
  test "owner finds a guest from Hôm nay without typing diacritics and opens the booking" do
    travel_to Time.zone.local(2026, 10, 10, 9)
    booking = rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-22", guest_name: "Anh Mai Đức", guest_phone: "0905123456")
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    find("a[aria-label='Tìm đặt phòng']").click
    fill_in "Tìm đặt phòng", with: "mai duc\n"
    within("#upcoming") { assert_text "1"; click_link "Anh Mai Đức" }
    assert_current_path pms_booking_path(booking)
    assert_text booking.code
  end
end
