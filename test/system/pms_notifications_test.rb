require "application_system_test_case"

class PmsNotificationsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "owner opens Thông báo from Hôm nay, reads all, undoes it and turns a type off" do
    rooms(:limdim).bookings.create!(start_date: Date.current + 3, end_date: Date.current + 5, guest_name: "Chị Hoa", price: 300_000)
      .payments.create!(amount: 300_000, payment_method: "bank")
    perform_enqueued_jobs
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    find("a[aria-label='Thông báo, 2 chưa đọc']").click
    assert_selector "header", text: "2 chưa đọc"
    assert_link "Chưa đọc · 2"
    click_button "Đọc hết"
    assert_selector ".pms-toast", text: "Đã đánh dấu 2 thông báo là đã đọc"
    assert_selector "header", text: "Đã đọc hết"
    within(".pms-toast") { click_button "Hoàn tác" }
    assert_selector "header", text: "2 chưa đọc"

    click_link "Thu tiền"
    assert_current_path %r{/dat-phong/\d+}
    go_back
    find("button[aria-label='Cài đặt thông báo']").click
    within("#settings_sheet") { find("label", text: "Tiền").click }
    assert_selector "#settings_sheet:popover-open"
    assert_no_selector "a", text: "Thu tiền"
    assert_equal %w[money room], users(:owner).reload.notifications_off.sort
  end
end
