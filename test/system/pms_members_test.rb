require "application_system_test_case"

class PmsMembersTest < ApplicationSystemTestCase
  test "owner invites a staff member, gets the link, gives a right and reads Nhật ký" do
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    within("nav[aria-label='Điều hướng chính']") { click_link "Thêm" }
    click_link "Nhân viên và nhật ký"
    click_button "+ Mời nhân viên"
    within("#member_sheet_new") do
      fill_in "Tên", with: "Anh Tú"
      fill_in "Số điện thoại", with: "0911222333"
      click_button "Thêm và lấy link"
    end
    within("#link_sheet") do
      assert_text "Gửi link cho Anh Tú"
      assert_field "Link liên kết", with: %r{/dat-mat-khau/}
      click_button "Đóng"
    end

    membership = places(:tomo).place_memberships.joins(:user).find_by!(users: { name: "Anh Tú" })
    find("##{dom_id(membership)}").click
    within("#sheet_#{dom_id(membership)}") do
      check "Xem báo cáo", allow_label_click: true
      click_button "Lưu"
    end
    assert_selector ".pms-toast", text: "Đã lưu quyền của Anh Tú"
    assert_equal %w[discount report], membership.reload.permissions.sort

    click_link "Nhật ký"
    assert_selector "[aria-label='Nhật ký thao tác']", text: "Anh Tú"
  end
end
