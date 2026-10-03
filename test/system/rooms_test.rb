require "application_system_test_case"

class RoomsTest < ApplicationSystemTestCase
  setup do
    visit new_session_path
    fill_in "Số điện thoại", with: "0912 345 678"
    fill_in "Mật khẩu", with: "password123"
    click_button "Đăng nhập"
    assert_selector "h1", text: "Tổng quan"
  end

  test "owner adds a room from the dashboard" do
    click_on "tomo homestay"
    click_on "Thêm phòng", match: :first
    fill_in "Tên phòng", with: "Mây"
    fill_in "Số khách tối đa", with: "2"
    fill_in "Giá mỗi đêm (₫)", with: "300.000"
    click_button "Lưu"

    assert_text "Đã lưu phòng."
    within "#room_#{Room.find_by!(name: "Mây").id}" do
      assert_text "300.000 ₫/đêm"
      assert_selector "[data-state]", text: "Trống"
    end
  end

  test "owner switches a room off with the toggle" do
    visit admin_place_path("tomo-homestay")
    within "#room_#{rooms(:garden).id}" do
      find("input[type=checkbox][name='room[active]']").click
    end
    within "#room_#{rooms(:garden).id}" do
      assert_selector "[data-state]", text: "Đã tắt"
    end
    assert_not rooms(:garden).reload.active?
  end
end
