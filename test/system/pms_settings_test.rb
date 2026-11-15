require "application_system_test_case"

class PmsSettingsTest < ApplicationSystemTestCase
  test "owner sets the bank account and adds a Dịch vụ from Cài đặt cơ sở" do
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    within("nav[aria-label='Điều hướng chính']") { click_link "Thêm" }
    click_link "Cài đặt cơ sở"
    fill_in "Ngân hàng", with: "Vietcombank"
    fill_in "Số tài khoản", with: "0123456789"
    fill_in "Chủ tài khoản", with: "NGUYEN THI LAN"
    click_button "Lưu tài khoản"
    assert_selector ".pms-toast", text: "Đã lưu tài khoản chuyển khoản"

    click_button "+ Thêm dịch vụ"
    within("#service_sheet_new") do
      fill_in "Tên dịch vụ", with: "Giặt ủi"
      fill_in "Giá (đ)", with: "30000"
      assert_field "Giá (đ)", with: "30.000"
      fill_in "Đơn vị", with: "kg"
      click_button "Thêm dịch vụ"
    end
    assert_selector ".pms-toast", text: "Đã thêm dịch vụ Giặt ủi"
    assert_selector "button", text: /Giặt ủi\s*30.000đ \/ kg/
    assert_equal [ "Vietcombank", 30_000 ], [ places(:tomo).reload.bank_name, places(:tomo).services.sole.price ]
  end
end
