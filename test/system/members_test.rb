require "application_system_test_case"

class MembersTest < ApplicationSystemTestCase
  test "owner adds staff, who links Zalo, takes a booking, and can't edit rooms" do
    travel_to Time.zone.local(2026, 10, 1, 12)
    log_in_with_zalo
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
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-hang")
    click_button "Liên kết Zalo"
    assert_selector "h1", text: "Tổng quan"
    visit admin_place_path("tomo-homestay")
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
