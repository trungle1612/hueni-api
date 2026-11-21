require "application_system_test_case"

class PmsBookingRequestsTest < ApplicationSystemTestCase
  setup do
    rooms(:garden).update!(room_type: "double", price: 400_000)
    @place = places(:tomo)
    site_ready(@place)
    @place.update!(site_open: true, site_deposit_percent: 30)
  end

  def ask(name, from) = @place.book_online(room_type: "double", start_date: from, end_date: from + 1, guests: 2, guest_name: name, guest_phone: "0905111333")

  test "owner accepts one request with a deposit and declines another with a reason" do
    day = Date.current + 10
    first, second = ask("Chị Hoa", day), ask("Anh Tú", day + 3)

    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"
    within("nav[aria-label='Điều hướng chính']") { click_link "Thêm" }
    click_link "Yêu cầu đặt phòng"
    assert_link "Chờ trả lời · 2"

    within("##{dom_id(first)}") { click_button "Nhận" }
    within("##{dom_id(first, :accept)}") do
      assert_text "Vui lòng chuyển cọc 120.000đ"
      find("label", text: "Không cọc").click
      assert_text "Không cần cọc, thanh toán khi nhận phòng."
      assert_no_text "Vui lòng chuyển cọc"
      find("label", text: "50%").click
      assert_text "Vui lòng chuyển cọc 200.000đ"
      click_button "Nhận và báo khách"
    end
    assert_selector ".pms-toast", text: "Đã nhận, tạo đặt phòng"
    assert_link "Xem đặt phòng"
    assert_equal [ "accepted", 50 ], first.reload.values_at(:status, :deposit_percent)

    click_link "Chờ trả lời · 1"
    within("##{dom_id(second)}") { click_button "Từ chối" }
    within("##{dom_id(second, :decline)}") do
      find("label", text: "Không nhận khách những ngày này").click
      click_button "Từ chối"
    end
    assert_selector ".pms-toast", text: "Đã từ chối và báo khách"
    assert_text "Từ chối: không nhận khách những ngày này"
    assert_equal [ "declined", "dates" ], second.reload.values_at(:status, :decline_reason)
  end
end
