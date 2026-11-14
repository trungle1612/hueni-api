require "application_system_test_case"

class PmsTodayTest < ApplicationSystemTestCase
  test "owner checks a guest in from Hôm nay, collecting what is due, then undoes it" do
    travel_to Time.zone.local(2026, 10, 1, 14)
    booking = bookings(:limdim_confirmed) # 1/10–3/10, Anh Minh
    booking.update!(price: 200_000)
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    within("#today_booking_#{booking.id}") { assert_text "Còn thu 400.000đ" }
    within("#today_booking_#{booking.id}") { click_button "Nhận" }
    within("[role=dialog]") do
      fill_in "Số khách", with: 2
      click_button "Đã thu 400.000đ, nhận phòng"
    end

    assert_selector ".pms-toast", text: "Đã nhận phòng Limdim · đã thu 400.000đ"
    assert_selector "#today_booking_#{booking.id}", text: "Đã nhận"
    within(".pms-toast") { click_button "Hoàn tác" }
    assert_selector "section[aria-labelledby=nhan-phong]", text: "Anh Minh"
    assert_nil booking.reload.checked_in_at
  end
end
