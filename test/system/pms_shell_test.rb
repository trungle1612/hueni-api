require "application_system_test_case"

class PmsShellTest < ApplicationSystemTestCase
  test "owner opens the PWA, logs in with Zalo, switches homestay and logs out" do
    PlaceMembership.create!(user: users(:owner), place: places(:hiuhill), role: "staff")
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")

    visit pms_today_path
    assert_selector "h1", text: "Đăng nhập bằng Zalo"
    click_button "Đăng nhập bằng Zalo"

    assert_current_path pms_today_path
    assert_selector "header", text: "Hiu Hill Homestay" # first by name

    click_link "Thêm"
    within("section", text: "Cơ sở") { click_button "tomo homestay" }
    assert_current_path pms_today_path
    assert_selector "header", text: "tomo homestay"

    click_link "Thêm"
    click_button "Đăng xuất"
    assert_current_path new_session_path
  end
end
