require "application_system_test_case"

class PmsRoomsTest < ApplicationSystemTestCase
  test "owner marks a room cleaned, sets Bảo trì from its sheet, then adds a room" do
    travel_to Time.zone.local(2026, 10, 2, 9)
    rooms(:garden).update!(housekeeping: "dirty")
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-chi-lan")
    visit pms_today_path
    click_button "Đăng nhập bằng Zalo"

    within("nav[aria-label='Điều hướng chính']") { click_link "Phòng" }
    within("#room_#{rooms(:garden).id}") { click_button "Đã dọn" }
    assert_selector ".pms-toast", text: "Phòng Garden: đã dọn, sẵn sàng đón khách"
    assert_selector "#room_#{rooms(:garden).id}", text: "Sẵn sàng"

    find("#room_#{rooms(:garden).id} button[popovertarget]").click
    within("#sheet_room_#{rooms(:garden).id}") do
      choose "Bảo trì", allow_label_click: true
      fill_in "Lý do bảo trì", with: "Sơn lại"
      fill_in "Dự kiến xong", with: Date.new(2026, 10, 5)
      click_button "Lưu tình trạng"
    end
    assert_selector ".pms-toast", text: "Phòng Garden bảo trì đến 05/10"
    assert_selector "#room_#{rooms(:garden).id}", text: "Sơn lại · đến 05/10"

    click_link "+ Thêm phòng"
    fill_in "Số phòng", with: "103"
    select "Phòng gia đình", from: "Loại phòng"
    fill_in "Số khách tối đa", with: 4
    fill_in "Giá mỗi đêm (đ)", with: "450000"
    assert_field "Giá mỗi đêm (đ)", with: "450.000"
    fill_in "Thứ 6, thứ 7 (đ)", with: "500k"
    assert_field "Thứ 6, thứ 7 (đ)", with: "500k"
    check "Máy lạnh", allow_label_click: true
    click_button "Thêm phòng"

    assert_selector ".pms-toast", text: "Đã thêm phòng 103"
    room = places(:tomo).rooms.find_by!(name: "103")
    assert_equal [ "family", 4, 450_000, 500_000, [ "ac" ] ], room.values_at(:room_type, :max_guests, :price, :weekend_price, :amenities)
  end

  # #259: a slow save locks its button with "Đang lưu…"; the old screen stays until the answer.
  test "a save button reads Đang lưu… and is locked while the form is sent" do
    log_in_with_zalo
    visit edit_pms_room_path(rooms(:garden))
    page.execute_script(<<~JS)
      const fetch = window.fetch
      window.fetch = (...args) => new Promise(resolve => setTimeout(() => resolve(fetch(...args)), 1500))
    JS
    fill_in "Ghi chú nội bộ", with: "Gần cầu thang"
    click_button "Lưu thay đổi"

    assert_button "Đang lưu…", disabled: true
    assert_selector "button[aria-busy='true']", text: "Đang lưu…"
    assert_selector "h1", text: "Sửa phòng Garden"
    assert_selector ".pms-toast", text: "Đã lưu phòng Garden."
    assert_equal "Gần cầu thang", rooms(:garden).reload.note
  end

  test "Ảnh phòng: the browser shrinks a chosen photo to 1600px before it is sent" do
    log_in_with_zalo
    visit edit_pms_room_path(rooms(:garden))
    attach_file "Thêm ảnh", file_fixture("room.jpg") # 2400 × 1200
    assert_no_selector "button[form=room_form][aria-busy]"
    size = evaluate_async_script(<<~JS)
      const file = document.getElementById("room_photo_files").files[0]
      createImageBitmap(file).then(b => arguments[0]([ file.type, file.name, b.width, b.height ]))
    JS
    assert_equal [ "image/jpeg", "room.jpg", 1600, 800 ], size

    click_button "Lưu thay đổi"
    assert_selector ".pms-toast", text: "Đã lưu phòng Garden"
    assert_equal 1, rooms(:garden).photos.count
  end
end
