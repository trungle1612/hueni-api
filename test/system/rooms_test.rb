require "application_system_test_case"

class RoomsTest < ApplicationSystemTestCase
  setup do
    log_in_with_zalo
  end

  test "owner adds a room from Phòng" do
    within("aside") { click_on "Phòng" }
    click_on "+ Thêm phòng"
    fill_in "Tên phòng", with: "Mây"
    fill_in "Số khách tối đa", with: "2"
    fill_in "Giá mỗi đêm (₫)", with: "300.000"
    click_button "Lưu"

    assert_text "Đã lưu phòng Mây."
    within("#room_#{Room.find_by!(name: "Mây").id}") { assert_text "2 khách · 300.000 ₫/đêm" }
  end

  test "owner pauses a room" do
    visit admin_rooms_path
    within("#room_#{rooms(:garden).id}") { click_on "Sửa" }
    choose "Tạm ngưng"
    click_button "Lưu"

    within("#room_#{rooms(:garden).id}") { assert_text "Tạm ngưng" }
    assert_not rooms(:garden).reload.active?
  end
end
