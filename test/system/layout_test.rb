require "application_system_test_case"

class LayoutTest < ApplicationSystemTestCase
  test "the desktop sidebar stays one screen tall and in view on a long page" do
    12.times { |i| places(:tomo).rooms.create!(name: "Phòng thêm #{i}", max_guests: 2) }
    visit new_session_path
    fill_in "Số điện thoại", with: "0912 345 678"
    fill_in "Mật khẩu", with: "password123"
    click_button "Đăng nhập"
    assert_selector "h1", text: "Tổng quan"
    visit admin_place_path("tomo-homestay")

    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    top, bottom, viewport = page.evaluate_script("(() => { const r = document.querySelector('aside').getBoundingClientRect(); return [r.top, r.bottom, window.innerHeight] })()")
    assert_equal [ 0, viewport ], [ top.round, bottom.round ]
    within("aside") { assert_selector "button", text: "Đăng xuất", visible: true }
  end
end
