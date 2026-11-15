require "application_system_test_case"

class PmsMoreTest < ApplicationSystemTestCase
  test "staff reads Điều khoản from Thêm, then deletes their account" do
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    users(:admin).update!(zalo_id: "zalo-admin")
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-admin")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    within("nav[aria-label='Điều hướng chính']") { click_link "Thêm" }
    click_link "Điều khoản và quyền riêng tư"
    find("summary", text: "Phạm vi và chấp nhận").click
    assert_text "Bạn chấp nhận điều khoản khi tích ô đồng ý."
    click_link "Chính sách bảo mật"
    assert_selector "nav a[aria-current=page]", text: "Chính sách bảo mật"
    find("a[aria-label='Quay lại']").click

    find("button", text: "Xoá tài khoản", match: :first).click
    within("#delete_sheet") do
      assert_text "Cơ sở vẫn giữ đặt phòng, tiền thu"
      click_button "Xoá tài khoản"
    end
    assert_text "Đã xoá tài khoản."
    assert users(:admin).reload.deleted?
  end
end
