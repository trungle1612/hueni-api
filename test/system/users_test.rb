require "application_system_test_case"

class UsersTest < ApplicationSystemTestCase
  def log_in(phone, password)
    visit new_session_path
    fill_in "Số điện thoại", with: phone
    fill_in "Mật khẩu", with: password
    click_button "Đăng nhập"
    assert_selector "h1", text: "Tổng quan"
  end

  test "admin creates an owner, who sets their own password from the link and sees their homestay" do
    log_in "0905 111 222", "password123"
    click_on "Người dùng", match: :first
    click_on "+ Thêm"
    fill_in "Tên", with: "Chị Hoa"
    fill_in "Số điện thoại (dùng để đăng nhập)", with: "+84 987 654 321"
    check "Hiu Hill Homestay"
    click_button "Tạo tài khoản"

    assert_text "Đã tạo tài khoản."
    link = find("[data-setup-link]").text
    click_button "Đăng xuất", match: :first
    assert_current_path new_session_path

    visit link
    assert_text "Chị Hoa"
    fill_in "Mật khẩu mới", with: "hoa-hue-2026"
    fill_in "Nhập lại mật khẩu", with: "hoa-hue-2026"
    click_button "Lưu mật khẩu"
    assert_text "Hiu Hill Homestay"
    assert_no_text "tomo homestay"

    click_button "Đăng xuất", match: :first
    assert_current_path new_session_path
    log_in "0987654321", "hoa-hue-2026"
    assert_text "Hiu Hill Homestay"
    assert_no_text "tomo homestay"
  end
end
