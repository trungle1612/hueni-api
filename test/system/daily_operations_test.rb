require "application_system_test_case"

class DailyOperationsTest < ApplicationSystemTestCase
  setup do
    log_in_with_zalo
  end

  test "check a late guest in, check them out from the booking page, then mark the room clean" do
    booking = rooms(:garden).bookings.create!(start_date: Date.yesterday, end_date: Date.tomorrow, guest_name: "Chị Mai")
    visit admin_root_path
    within("#tile_room_#{rooms(:garden).id}") { assert_text "Chờ khách" }

    within("#today_booking_#{booking.id}") do
      assert_text "Trễ 1 ngày"
      fill_in "Số khách", with: 2
      accept_confirm("Chị Mai nhận phòng Garden?") { click_button "Nhận phòng" }
    end
    assert_text "Đã nhận phòng: Chị Mai · Garden"
    within("#tile_room_#{rooms(:garden).id}") { assert_text "Đang có khách" }
    within("#in_house") { click_button "Đã khai báo" }
    assert_text "Đã khai báo lưu trú: Chị Mai · Garden"

    within("#in_house") { click_on "Chị Mai" }
    accept_confirm("Chị Mai trả phòng Garden?") { click_button "Trả phòng" }
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
      fill_in "Số khách", with: 2
      accept_confirm(/Chị Hoa nhận phòng sớm Garden\? Ngày đến đổi/) { click_button "Nhận phòng sớm" }
    end
    assert_text "Đã nhận phòng: Chị Hoa · Garden"
    within("#room_#{rooms(:garden).id}") { assert_text "Đang có khách" }
    assert_equal Date.current, booking.reload.start_date
  end
end
