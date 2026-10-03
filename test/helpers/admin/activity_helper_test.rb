require "test_helper"

class Admin::ActivityHelperTest < ActionView::TestCase
  include Admin::RoomsHelper

  setup { travel_to Time.zone.local(2026, 10, 5, 12) }

  def entry = activity_entry(PaperTrail::Version.last).values_at(:kind, :action, :detail)

  test "booking rows" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07", status: "hold", guest_name: "Chị Mai")
    assert_equal [ :booking, "Giữ chỗ", "Chị Mai 05/10–07/10" ], entry

    booking.update!(status: "confirmed")
    assert_equal [ :booking, "Xác nhận", "Chị Mai 05/10–07/10" ], entry

    booking.update!(start_date: "2026-10-06", end_date: "2026-10-08", guests: 2, guest_phone: "0905000111")
    assert_equal [ :edit, "Sửa đặt phòng", "Chị Mai: đổi ngày 05/10–07/10 → 06/10–08/10, SĐT: — → 0905000111, số khách: — → 2" ], entry

    booking.update!(note: "Đến muộn")
    assert_equal [ :edit, "Sửa đặt phòng", "Chị Mai: sửa ghi chú" ], entry

    booking.update!(guest_name: "")
    assert_equal [ :edit, "Sửa đặt phòng", "khách: Chị Mai → —" ], entry

    booking.update!(guest_name: "Chị Mai", start_date: "2026-10-05")
    booking.check_in
    assert_equal [ :check_in, "Nhận phòng", "Chị Mai" ], entry
    booking.check_out
    assert_equal [ :check_out, "Trả phòng", "Chị Mai" ], entry

    other = rooms(:limdim).bookings.create!(start_date: "2026-10-10", end_date: "2026-10-12")
    assert_equal [ :booking, "Đặt phòng", "10/10–12/10" ], entry
    other.update!(status: "cancelled")
    assert_equal [ :cancel, "Huỷ", "10/10–12/10" ], entry
  end

  test "check-in and check-out of a stay without a guest name show its dates" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07")
    booking.check_in
    assert_equal [ :check_in, "Nhận phòng", "Khách 05/10–07/10" ], entry
    booking.check_out
    assert_equal [ :check_out, "Trả phòng", "Khách 05/10–07/10" ], entry
  end

  test "OTA sync rows" do
    feed = calendar_feeds(:limdim_airbnb)
    booking = PaperTrail.request(whodunnit: "airbnb") do
      feed.bookings.create!(room: rooms(:limdim), uid: "a", start_date: "2026-10-12", end_date: "2026-10-14", source: "ical")
    end
    assert_equal [ :sync, "Đặt phòng", "12/10–14/10" ], entry
    PaperTrail.request(whodunnit: "airbnb") { booking.update!(start_date: "2026-10-13", end_date: "2026-10-15") }
    assert_equal [ :sync, "Đổi ngày", "12/10–14/10 → 13/10–15/10" ], entry
    PaperTrail.request(whodunnit: "airbnb") { booking.destroy! }
    assert_equal [ :sync, "Xoá đặt phòng", "13/10–15/10" ], entry
  end

  test "room rows" do
    room = places(:tomo).rooms.create!(name: "Mây", max_guests: 2)
    assert_equal [ :room, "Thêm phòng", nil ], entry
    room.update!(name: "Mây Trắng", price: 350_000, max_guests: 3)
    assert_equal [ :room, "Sửa phòng", "đổi tên Mây → Mây Trắng, giá chưa có → 350.000 ₫, tối đa 2 → 3 khách" ], entry
    room.update!(active: false)
    assert_equal [ :room, "Tắt phòng", nil ], entry
    room.update!(active: true)
    assert_equal [ :room, "Bật phòng", nil ], entry
    room.dirty!
    room.clean!
    assert_equal [ :clean, "Dọn xong", nil ], entry
  end

  test "feed rows" do
    feed = rooms(:garden).calendar_feeds.create!(url: "https://1.1.1.1/x.ics", provider: "booking")
    assert_equal [ :feed, "Thêm kênh", "Booking.com" ], entry
    feed.update!(last_error: "RuntimeError: HTTP 404")
    assert_equal [ :error, "Đồng bộ lỗi", "RuntimeError: HTTP 404" ], entry
    feed.update!(last_error: nil)
    assert_equal [ :ok, "Đồng bộ lại được", nil ], entry
    feed.destroy!
    assert_equal [ :feed, "Xoá kênh", "Booking.com" ], entry
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
