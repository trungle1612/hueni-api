require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  test "owner logs in, lands on the page they asked for, and logs out" do
    visit admin_root_path
    assert_current_path new_session_path

    fill_in "Số điện thoại", with: "0912 345 678"
    fill_in "Mật khẩu", with: "password123"
    click_button "Đăng nhập"

    assert_current_path admin_root_path
    assert_selector "h1", text: "Tổng quan"
    assert_text "Chị Lan"

    click_button "Đăng xuất"
    assert_current_path new_session_path
  end

  test "wrong password shows the error" do
    visit new_session_path
    fill_in "Số điện thoại", with: "0912 345 678"
    fill_in "Mật khẩu", with: "wrong-password"
    click_button "Đăng nhập"

    assert_text "Số điện thoại hoặc mật khẩu không đúng"
  end
end
