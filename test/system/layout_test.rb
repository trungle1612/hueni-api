require "application_system_test_case"

class LayoutTest < ApplicationSystemTestCase
  test "the desktop sidebar stays one screen tall and in view on a long page" do
    30.times { |i| User.create!(name: "Người dùng #{i}", phone_number: "09870000#{i.to_s.rjust(2, "0")}", password: "password123") }
    users(:admin).update!(zalo_id: "zalo-trung")
    log_in_with_zalo "zalo-trung"
    visit admin_users_path

    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
    top, bottom, viewport = page.evaluate_script("(() => { const r = document.querySelector('aside').getBoundingClientRect(); return [r.top, r.bottom, window.innerHeight] })()")
    assert_equal [ 0, viewport ], [ top.round, bottom.round ]
    within("aside") { assert_selector "button", text: "Đăng xuất", visible: true }
  end
end
