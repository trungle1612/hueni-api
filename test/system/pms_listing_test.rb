require "application_system_test_case"

class PmsListingTest < ApplicationSystemTestCase
  test "owner fills Giờ nhận, trả phòng, turns Hiển thị trên hue-ni on and saves" do
    rooms(:garden).update!(room_type: "double", price: 400_000)
    place = places(:tomo)
    site_ready(place)
    place.update!(check_in_time: nil, check_out_time: nil)

    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    within("nav[aria-label='Điều hướng chính']") { click_link "Thêm" }
    click_link "Hiển thị trên hue-ni"
    assert_selector "input[name='listing[open]'][type=checkbox]:disabled"
    click_button "Giờ nhận, trả phòng"
    within("#rules_sheet") do
      fill_in "Giờ nhận phòng", with: Time.new(2000, 1, 1, 14, 0)
      fill_in "Giờ trả phòng", with: Time.new(2000, 1, 1, 12, 0)
      fill_in "Quy định", with: "Không hút thuốc trong phòng."
      click_button "Lưu"
    end
    assert_selector ".pms-toast", text: "Đã cập nhật. hue-ni hiển thị thay đổi trong vài phút."
    assert_text "4 / 4 đã xong"

    find("input[name='listing[open]'][type=checkbox]").check
    find("label", text: "Tự nhận khi còn phòng").click
    click_button "Lưu thay đổi"
    assert_selector ".pms-toast", text: "Đã cập nhật. hue-ni hiển thị thay đổi trong vài phút."
    assert_text "Đang hiện và nhận yêu cầu"
    assert_selector "#preview", text: "Đặt phòng"
    assert_equal [ true, "auto", "Không hút thuốc trong phòng." ], place.reload.values_at(:site_open, :site_mode, :house_rules)
  end
end
