require "application_system_test_case"

class LayoutTest < ApplicationSystemTestCase
  test "the desktop sidebar stays one screen tall and in view on a long page" do
    12.times { |i| places(:tomo).rooms.create!(name: "Phòng thêm #{i}", max_guests: 2) }
    log_in_with_zalo
    visit admin_place_path("tomo-homestay")

    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    top, bottom, viewport = page.evaluate_script("(() => { const r = document.querySelector('aside').getBoundingClientRect(); return [r.top, r.bottom, window.innerHeight] })()")
    assert_equal [ 0, viewport ], [ top.round, bottom.round ]
    within("aside") { assert_selector "button", text: "Đăng xuất", visible: true }
  end
end
