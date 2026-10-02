require "application_system_test_case"

class CalendarTest < ApplicationSystemTestCase
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12) # limdim_confirmed occupies Limdim 10-01..10-03
    visit new_session_path
    fill_in "Email", with: "lan@example.com"
    fill_in "Mật khẩu", with: "password123"
    click_button "Đăng nhập"
    assert_selector "h1", text: "Tổng quan"
  end

  # Straight from the server: the browser would reuse the endpoint's 1-minute public cache.
  def tomo_rooms_left
    JSON.parse(Net::HTTP.get(URI("#{Capybara.current_session.server.base_url}/v1/vacancy"))).dig("places", "tomo-homestay", "left")
  end

  test "owner holds a room, vacancy shows it booked; cancelling frees it again" do
    assert_equal 1, tomo_rooms_left

    click_on "Lịch phòng", match: :first
    find("a[aria-label='Đặt Garden ngày 01/10']").click
    assert_select "Phòng", selected: "Garden"
    choose "Giữ chỗ"
    fill_in "Tên khách", with: "Chị Mai"
    fill_in "Số điện thoại", with: "0905 123 456"
    click_button "Lưu"

    assert_text "Đã lưu đặt phòng."
    assert_selector "[data-room='#{rooms(:garden).id}'] a", text: "Chị Mai"
    assert_equal 0, tomo_rooms_left

    click_on "Chị Mai"
    assert_selector "a[href='tel:0905123456']"
    accept_confirm { click_button "Huỷ đặt phòng" }

    assert_text "Đã huỷ đặt phòng."
    assert_no_text "Chị Mai"
    assert_equal 1, tomo_rooms_left
    assert Booking.find_by!(guest_name: "Chị Mai").cancelled?
  end

  test "overlapping booking on the same room is rejected" do
    visit admin_place_calendar_path("tomo-homestay")
    click_on "+ Đặt phòng"
    select "Limdim", from: "Phòng"
    fill_in "Nhận phòng", with: Date.new(2026, 10, 2)
    fill_in "Trả phòng", with: Date.new(2026, 10, 4)
    click_button "Lưu"

    assert_text "Phòng đã có người đặt trong khoảng ngày này"
    assert_equal 1, rooms(:limdim).bookings.count
  end

  test "iCal booking overlapping a manual one is shown as a conflict" do
    Booking.create!(room: rooms(:limdim), start_date: "2026-10-02", end_date: "2026-10-05", source: "ical",
      calendar_feed: calendar_feeds(:limdim_airbnb), uid: "a")

    visit admin_place_calendar_path("tomo-homestay")
    within "[data-room='#{rooms(:limdim).id}']" do
      assert_selector "[data-conflict]", count: 2
      assert_text "⚠"
    end
    assert_text "Limdim: Airbnb 02/10–05/10 trùng với “Anh Minh”"
  end
end
