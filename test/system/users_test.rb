require "application_system_test_case"

class UsersTest < ApplicationSystemTestCase
  def log_in(phone, password)
    visit new_session_path
    fill_in "Số điện thoại", with: phone
    fill_in "Mật khẩu", with: password
    click_button "Đăng nhập"
    assert_selector "h1", text: "Tổng quan"
  end

  test "admin creates an owner, who logs in with the generated password and sees their homestay" do
    log_in "0905 111 222", "password123"
    click_on "Người dùng", match: :first
    click_on "+ Thêm"
    fill_in "Tên", with: "Chị Hoa"
    fill_in "Số điện thoại (dùng để đăng nhập)", with: "+84 987 654 321"
    check "Hiu Hill Homestay"
    click_button "Tạo tài khoản"

    assert_text "Đã tạo tài khoản."
    password = find("[data-new-password]").text
    assert_text "0987 654 321"

    click_button "Đăng xuất", match: :first
    log_in "0987654321", password
    assert_text "Hiu Hill Homestay"
    assert_no_text "tomo homestay"
  end
end
