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

  test "owner gives a discount, refunds part of the deposit and moves the guest after check-in" do
    travel_to Time.zone.local(2026, 10, 1, 14)
    booking = bookings(:limdim_confirmed)
    booking.update!(price: 200_000, guests: 2)
    booking.payments.create!(amount: 100_000, payment_method: "cash")
    booking.check_in
    log_in_with_zalo
    visit pms_booking_path(booking)

    click_button "Giảm giá"
    within("[role=dialog]#discount-sheet") do
      fill_in "Số tiền hoặc %", with: "10%"
      fill_in "Lý do", with: "Khách quen"
      click_button "Lưu giảm giá"
    end
    assert_selector ".pms-toast", text: "Đã giảm 40.000đ"

    click_button "Hoàn tiền"
    within("[role=dialog]#give-back") do
      fill_in "Số tiền (đ)", with: "30k"
      click_button "Hoàn tiền"
    end
    assert_selector ".pms-toast", text: "Đã hoàn 30.000đ · Tiền mặt"

    click_button "Đổi phòng"
    within("[role=dialog]#move") do
      choose "Garden", allow_label_click: true
      click_button "Đổi phòng"
    end
    assert_selector ".pms-toast", text: "Đã đổi phòng Limdim → Garden"
    assert_equal [ rooms(:garden), 40_000, 70_000 ], [ booking.reload.room, booking.discount, booking.paid ]
  end
end
