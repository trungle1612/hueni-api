require "application_system_test_case"

class MembersTest < ApplicationSystemTestCase
  def log_in(phone, password)
    visit new_session_path
    fill_in "Số điện thoại", with: phone
    fill_in "Mật khẩu", with: password
    click_button "Đăng nhập"
    assert_selector "h1", text: "Tổng quan"
  end

  test "owner adds staff, who sets a password, takes a booking, and can't edit rooms" do
    travel_to Time.zone.local(2026, 10, 1, 12)
    log_in "0912 345 678", "password123"
    click_on "tomo homestay"
    within("#members") { click_on "+ Thêm" }
    fill_in "Tên", with: "Em Hằng"
    fill_in "Số điện thoại", with: "0987 111 222"
    choose "Nhân viên"
    click_button "Thêm và lấy link"
    link = find("[data-setup-link]").text
    click_button "Đăng xuất", match: :first
    assert_current_path new_session_path

    visit link
    fill_in "Mật khẩu mới", with: "hang-hue-2026"
    fill_in "Nhập lại mật khẩu", with: "hang-hue-2026"
    click_button "Lưu mật khẩu"
    assert_selector ".badge", text: "Nhân viên"

    visit admin_place_calendar_path("tomo-homestay")
    find("a[aria-label='Đặt Garden ngày 05/10']").click
    fill_in "Tên khách", with: "Khách của Hằng"
    click_button "Lưu"
    assert_text "Đã lưu đặt phòng."

    visit edit_admin_room_path(rooms(:garden))
    assert_selector "h1", text: "Bạn không có quyền"
  end
end
