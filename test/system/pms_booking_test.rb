require "application_system_test_case"

class PmsBookingTest < ApplicationSystemTestCase
  test "owner opens a booking from Hôm nay, takes a payment, then edits its dates" do
    travel_to Time.zone.local(2026, 10, 1, 14)
    booking = bookings(:limdim_confirmed) # 1/10–3/10, Anh Minh
    booking.update!(price: 200_000)
    rooms(:limdim).bookings.create!(start_date: "2026-10-04", end_date: "2026-10-06", guest_name: "Cô Ba")
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    click_link "Anh Minh"
    assert_selector "h1", text: "Anh Minh"
    click_button "Ghi nhận thanh toán"
    within("[role=dialog]#pay") do
      fill_in "Số tiền (đ)", with: "150k"
      choose "Chuyển khoản", allow_label_click: true
      click_button "Ghi nhận"
    end
    assert_selector ".pms-toast", text: "Đã ghi nhận 150.000đ · Chuyển khoản"
    assert_selector "#due", text: "250.000đ"

    click_link "Sửa"
    fill_in "Trả phòng", with: Date.new(2026, 10, 5)
    assert_selector "#dates_error", text: "Phòng khác còn trống: Garden"
    fill_in "Trả phòng", with: Date.new(2026, 10, 4)
    assert_selector "turbo-frame#availability", text: "Không trùng lịch · 3 đêm"
    click_button "Lưu thay đổi"

    assert_selector ".pms-toast", text: "Đã lưu thay đổi"
    assert_selector "#due", text: "450.000đ"
    assert_equal Date.new(2026, 10, 4), booking.reload.end_date
  end
end
