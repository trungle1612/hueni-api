require "application_system_test_case"

class PmsOnboardingTest < ApplicationSystemTestCase
  test "first login in a browser: Bắt đầu one step at a time, then Hôm nay" do
    page.driver.browser.manage.delete_cookie("pms_onboarded")
    log_in_with_zalo

    assert_text "BƯỚC 1 / 2"
    assert_selector "h1", text: "Đặt hueni ra màn hình chính"
    click_button "Để sau"
    assert_text "BƯỚC 2 / 2"
    assert_selector "h1", text: "Chuẩn bị cơ sở của bạn"
    assert_no_selector "h1", text: "Đặt hueni ra màn hình chính"
    click_link "Vào Hôm nay"
    assert_current_path pms_today_path
    assert_selector "h1", text: "Hôm nay"
  end
end
