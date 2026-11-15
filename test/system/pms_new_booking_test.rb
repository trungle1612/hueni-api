require "application_system_test_case"

class PmsNewBookingTest < ApplicationSystemTestCase
  test "owner books a returning guest into a free room from Hôm nay" do
    travel_to Time.zone.local(2026, 10, 1, 14)
    rooms(:limdim).update!(price: 300_000)
    rooms(:garden).update!(price: 250_000)
    rooms(:garden).bookings.create!(start_date: "2026-09-10", end_date: "2026-09-12", guest_name: "Chị Hoa", guest_phone: "0905111333")
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    click_link "+ Đặt phòng"
    fill_in "Số điện thoại", with: "0905 111 333"
    within("#returning") { click_button "Dùng thông tin" }
    assert_field "Tên khách", with: "Chị Hoa"

    # Đóng with something typed asks first.
    find("a[aria-label='Đóng']").click
    within("#discard") { click_button "Tiếp tục nhập" }

    fill_in "Trả phòng", with: Date.new(2026, 10, 4)
    assert_selector "legend", text: "1 phòng trống 01 – 04/10"
    assert_selector "input[value='#{rooms(:limdim).id}'][disabled]", visible: :all
    fill_in "Đã cọc (đ)", with: "200k"
    assert_selector "#quote_footer", text: "750.000đ"
    assert_selector "#quote_footer", text: "còn thu 550.000đ"
    click_button "Lưu đặt phòng"

    assert_selector "[role=status]", text: "Đã lưu đặt phòng DP-"
    assert_selector "#summary", text: "Phòng Garden"
    booking = Booking.last
    assert_equal [ "Chị Hoa", rooms(:garden), 250_000, 200_000 ], [ booking.guest_name, booking.room, booking.price, booking.paid ]
    click_link "Đặt phòng khác"
    assert_selector "h1", text: "Đặt phòng mới"
  end
end
