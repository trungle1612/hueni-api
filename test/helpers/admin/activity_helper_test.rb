require "test_helper"

class Admin::ActivityHelperTest < ActionView::TestCase
  include Admin::RoomsHelper

  setup { travel_to Time.zone.local(2026, 10, 5, 12) }

  def text = activity_text(PaperTrail::Version.last)

  test "booking lines" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07", status: "hold", guest_name: "Chị Mai")
    assert_equal "giữ chỗ Chị Mai 05/10–07/10", text

    booking.update!(status: "confirmed")
    assert_equal "xác nhận Chị Mai 05/10–07/10", text

    booking.update!(start_date: "2026-10-06", end_date: "2026-10-08", guests: 2, guest_phone: "0905000111")
    assert_equal "đổi ngày 05/10–07/10 → 06/10–08/10, SĐT: — → 0905000111, số khách: — → 2", text

    booking.update!(note: "Đến muộn")
    assert_equal "sửa ghi chú", text

    booking.update!(guest_name: "")
    assert_equal "khách: Chị Mai → —", text

    booking.update!(guest_name: "Chị Mai", start_date: "2026-10-05")
    booking.check_in
    assert_equal "nhận phòng Chị Mai", text
    booking.check_out
    assert_equal "trả phòng Chị Mai", text

    other = rooms(:limdim).bookings.create!(start_date: "2026-10-10", end_date: "2026-10-12")
    other.update!(status: "cancelled")
    assert_equal "huỷ 10/10–12/10", text
  end

  test "iCal booking lines have no guest name" do
    feed = calendar_feeds(:limdim_airbnb)
    booking = feed.bookings.create!(room: rooms(:limdim), uid: "a", start_date: "2026-10-12", end_date: "2026-10-14", source: "ical")
    assert_equal "thêm đặt phòng 12/10–14/10", text
    booking.destroy!
    assert_equal "xoá đặt phòng 12/10–14/10", text
  end

  test "room lines" do
    room = places(:tomo).rooms.create!(name: "Mây", max_guests: 2)
    assert_equal "thêm phòng", text
    room.update!(name: "Mây Trắng", price: 350_000, max_guests: 3)
    assert_equal "đổi tên Mây → Mây Trắng, giá chưa có → 350.000 ₫, tối đa 2 → 3 khách", text
    room.update!(active: false)
    assert_equal "tắt phòng", text
    room.update!(active: true)
    assert_equal "bật phòng", text
    room.dirty!
    room.clean!
    assert_equal "dọn xong", text
  end

  test "feed lines" do
    feed = rooms(:garden).calendar_feeds.create!(url: "https://1.1.1.1/x.ics", provider: "booking")
    assert_equal "thêm kênh Booking.com", text
    feed.update!(last_error: "RuntimeError: HTTP 404")
    assert_equal "đồng bộ lỗi: RuntimeError: HTTP 404", text
    assert activity_error?(PaperTrail::Version.last)
    feed.update!(last_error: nil)
    assert_equal "đồng bộ lại được", text
    assert_not activity_error?(PaperTrail::Version.last)
    feed.destroy!
    assert_equal "xoá kênh Booking.com", text
  end

  test "who: user name, OTA label, or Hệ thống" do
    PaperTrail.request(whodunnit: users(:owner).id.to_s) { rooms(:garden).update!(max_guests: 3) }
    PaperTrail.request(whodunnit: "booking") { rooms(:garden).update!(max_guests: 4) }
    PaperTrail.request(whodunnit: "999999") { rooms(:garden).update!(max_guests: 5) }
    rooms(:garden).update!(max_guests: 6)

    names = activity_names(PaperTrail::Version.order(:id).to_a)
    assert_equal({ users(:owner).id.to_s => "Chị Lan", "booking" => "Booking.com", "999999" => "Hệ thống", nil => "Hệ thống" }, names)
    assert_equal({ rooms(:garden).id => "Garden" }, activity_room_names(PaperTrail::Version.all.to_a))
  end

  test "day headings" do
    assert_equal "Hôm nay", activity_day(Date.new(2026, 10, 5))
    assert_equal "Hôm qua", activity_day(Date.new(2026, 10, 4))
    assert_match %r{\AThứ hai 28/09\z}i, activity_day(Date.new(2026, 9, 28))
  end
end
