require "application_system_test_case"

class UsersTest < ApplicationSystemTestCase
  test "admin creates an owner, who links Zalo from the link and sees their homestay" do
    visit new_session_path
    find("summary", text: "Quản trị viên đăng nhập bằng mật khẩu").click
    fill_in "Số điện thoại", with: "0905 111 222"
    fill_in "Mật khẩu", with: "password123"
    click_button "Đăng nhập"
    click_on "Người dùng", match: :first
    click_on "+ Thêm"
    fill_in "Tên", with: "Chị Hoa"
    fill_in "Số điện thoại (dùng để đăng nhập)", with: "+84 987 654 321"
    select "Chủ", from: "memberships[#{places(:hiuhill).id}]"
    click_button "Tạo tài khoản"

    assert_text "Đã tạo tài khoản."
    link = find("[data-setup-link]").text
    click_button "Đăng xuất", match: :first
    assert_current_path new_session_path

    visit link
    assert_text "Chị Hoa"
    assert_no_field "Mật khẩu mới"
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-hoa")
    click_button "Liên kết Zalo"
    assert_text "Hiu Hill Homestay"
    assert_no_text "tomo homestay"

    click_button "Đăng xuất", match: :first
    assert_current_path new_session_path
    log_in_with_zalo "zalo-hoa"
    assert_text "Hiu Hill Homestay"
    assert_no_text "tomo homestay"
  end
end
