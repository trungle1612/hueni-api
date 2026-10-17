require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  test "owner logs in with Zalo, lands on the page they asked for, and logs out" do
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit admin_place_path("tomo-homestay")
    assert_current_path new_session_path

    click_button "Đăng nhập bằng Zalo"

    assert_current_path admin_place_path("tomo-homestay")
    assert_text "Chị Lan"

    click_button "Đăng xuất"
    assert_current_path new_session_path
  end

  test "admin logs in with the password form behind the link" do
    visit new_session_path
    assert_no_field "Mật khẩu"
    find("summary", text: "Quản trị viên đăng nhập bằng mật khẩu").click
    fill_in "Số điện thoại", with: "0905 111 222"
    fill_in "Mật khẩu", with: "password123"
    click_button "Đăng nhập"

    assert_selector "h1", text: "Tổng quan"
  end

  test "wrong password shows the error with the form open" do
    visit new_session_path
    find("summary", text: "Quản trị viên đăng nhập bằng mật khẩu").click
    fill_in "Số điện thoại", with: "0905 111 222"
    fill_in "Mật khẩu", with: "wrong-password"
    click_button "Đăng nhập"

    assert_text "Số điện thoại hoặc mật khẩu không đúng"
    assert_field "Mật khẩu"
  end
end
