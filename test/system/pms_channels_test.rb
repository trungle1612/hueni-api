require "application_system_test_case"

class PmsChannelsTest < ApplicationSystemTestCase
  URL = "https://1.1.1.1/calendar/ical/42.ics?s=secret-token"

  test "owner connects an Agoda link to a room and sets its commission from Kênh bán phòng" do
    stub_request(:get, URL).to_return(body: file_fixture("airbnb.ics").read)
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    within("nav[aria-label='Điều hướng chính']") { click_link "Thêm" }
    click_link "Kênh bán phòng (OTA)"
    find("#channel_agoda", text: "Chưa kết nối").click
    within("#channel_agoda_sheet") do
      select "Phòng Garden", from: "Phòng"
      fill_in "Link lịch của kênh", with: URL
      click_button "Kết nối"
    end
    assert_selector ".pms-toast", text: "Agoda đã đọc được lịch phòng Garden"

    find("#channel_agoda", text: "Đang chạy").click
    within("#channel_agoda_sheet") do
      assert_text "Phòng Garden"
      fill_in "Hoa hồng (%)", with: "18"
      click_button "Lưu hoa hồng"
    end
    assert_selector ".pms-toast", text: "Đã lưu hoa hồng"
    assert_selector "#channel_agoda", text: "hoa hồng 18%"
    assert_equal 18.0, places(:tomo).reload.commissions["agoda"]
    assert_button "Đồng bộ ngay"
  end
end
