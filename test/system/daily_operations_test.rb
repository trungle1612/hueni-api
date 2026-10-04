require "application_system_test_case"

class DailyOperationsTest < ApplicationSystemTestCase
  setup do
    visit new_session_path
    fill_in "Số điện thoại", with: "0912 345 678"
    fill_in "Mật khẩu", with: "password123"
    click_button "Đăng nhập"
    assert_selector "h1", text: "Tổng quan"
  end

  test "check a late guest in, check them out from the booking page, then mark the room clean" do
    booking = rooms(:garden).bookings.create!(start_date: Date.yesterday, end_date: Date.tomorrow, guest_name: "Chị Mai")
    visit admin_root_path
    within("#tile_room_#{rooms(:garden).id}") { assert_text "Chờ khách" }

    within("#today_booking_#{booking.id}") do
      assert_text "Trễ 1 ngày"
      accept_confirm("Chị Mai nhận phòng Garden?") { click_button "Check-in" }
    end
    assert_text "Đã nhận phòng: Chị Mai · Garden"
    within("#tile_room_#{rooms(:garden).id}") { assert_text "Đang có khách" }

    within("#in_house") { click_on "Chị Mai" }
    accept_confirm("Chị Mai trả phòng Garden?") { click_button "Check-out" }
    assert_text "Đã trả phòng: Chị Mai · Garden. Phòng chuyển sang chưa dọn."

    visit admin_root_path
    within("#dirty_rooms") { click_button "Dọn xong" }
    assert_text "Đã dọn xong Garden."
    assert_no_selector "#dirty_rooms"
    assert rooms(:garden).reload.clean?
  end

  test "check a guest in early from the homestay page" do
    booking = rooms(:garden).bookings.create!(start_date: Date.current + 2, end_date: Date.current + 4, guest_name: "Chị Hoa")
    visit admin_place_path("tomo-homestay")
    within("#room_#{rooms(:garden).id}") do
      accept_confirm(/Chị Hoa nhận phòng sớm Garden\? Ngày đến đổi/) { click_button "Nhận phòng sớm" }
    end
    assert_text "Đã nhận phòng: Chị Hoa · Garden"
    within("#room_#{rooms(:garden).id}") { assert_text "Đang có khách" }
    assert_equal Date.current, booking.reload.start_date
  end
end
