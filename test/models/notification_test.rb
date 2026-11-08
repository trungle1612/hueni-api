require "test_helper"

# Thông báo saved when the event happens (#216): by the model, with who did it, never from paper_trail.
class NotificationTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 11, 8, 14, 0)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
  end

  def signed_in(user, &) = Current.set(api_token: user.api_tokens.create!, &)
  def last = Notification.order(:id).last

  test "booking events, worded once and saved even with paper_trail off" do
    booking = PaperTrail.request(enabled: false) do
      signed_in(@staff) { rooms(:limdim).bookings.create!(start_date: "2026-11-08", end_date: "2026-11-10", guest_name: "Chị Hoa", guests: 2) }
    end
    assert_equal [ "booking", "Đặt phòng mới", "Chị Hoa 08/11–10/11 · Phòng #{rooms(:limdim).name}", "Bé Na", @staff.id, booking.id ],
      last.values_at(:kind, :title, :body, :source, :actor_id, :booking_id)

    signed_in(users(:owner)) { booking.update!(status: "cancelled", cancel_reason: "Khách huỷ") }
    assert_equal [ "cancel", "Chị Hoa 08/11–10/11 · Khách huỷ · Phòng #{rooms(:limdim).name}", "Chị Lan" ], last.values_at(:kind, :body, :source)
  end

  test "the OTA's and the guest's bookings name them; jobs are Hệ thống" do
    feed = calendar_feeds(:limdim_airbnb)
    ical = feed.bookings.create!(room: rooms(:limdim), uid: "x@airbnb.com", source: "ical", start_date: "2026-11-20", end_date: "2026-11-22")
    assert_equal [ "Airbnb", nil ], last.values_at(:source, :actor_id)
    ical.update!(checked_in_at: Time.current)
    ical.update!(removed_from_feed_at: Time.current)
    assert_equal [ "ota_removed", "Airbnb" ], last.values_at(:kind, :source)
    ical.update!(checked_in_at: nil)
    ical.destroy!
    assert_equal [ "ota_delete", nil, "Airbnb" ], last.values_at(:kind, :booking_id, :source)

    rooms(:garden).bookings.create!(start_date: "2026-11-25", end_date: "2026-11-26", guest_name: "Anh Tú", online: true)
    assert_equal "Khách đặt online", last.source
    rooms(:garden).bookings.create!(start_date: "2026-11-27", end_date: "2026-11-28", guest_name: "Chị Ba")
    assert_equal "Hệ thống", last.source
  end

  test "Thu tiền, Xin hoàn tiền, Chốt ca lệch, Dọn xong, Báo hỏng; a refund or a matching close is not one" do
    booking = PaperTrail.request(enabled: false) { rooms(:limdim).bookings.create!(start_date: "2026-11-08", end_date: "2026-11-10", guest_name: "Chị Hoa", price: 300_000) }
    signed_in(@staff) do
      assert_no_difference(-> { Notification.count }) { assert Shift.new(places(:tomo)).close(user: @staff, counted: 0, keep: 0).persisted? }
      assert Shift.new(places(:tomo)).close(user: @staff, counted: 50_000, keep: 0, note: "Đếm lại sau").persisted?
      assert_equal [ "shift", "Thừa 50.000 ₫ · Đếm lại sau" ], last.values_at(:kind, :body)

      booking.payments.create!(amount: 300_000, payment_method: "bank")
      assert_equal [ "payment", "300.000 ₫ · Chuyển khoản · #{booking.code} · Phòng #{rooms(:limdim).name}" ], last.values_at(:kind, :body)
      request = booking.refund_requests.create!(amount: 100_000, payment_method: "cash", requested_by: @staff)
      assert_equal [ "refund_request", request.id ], last.values_at(:kind, :refund_request_id)
      assert_no_difference -> { Notification.count } do
        booking.payments.create!(amount: 100_000, payment_method: "cash", kind: "refund")
      end

      rooms(:limdim).dirty!
      rooms(:limdim).clean!
      assert_equal [ "clean", "Phòng #{rooms(:limdim).name}" ], last.values_at(:kind, :body)
      rooms(:limdim).update!(damage_note: "Vỡ cốc")
      assert_equal [ "damage", "Vỡ cốc · Phòng #{rooms(:limdim).name}" ], last.values_at(:kind, :body)
    end
  end

  test "a refused Thu tiền và nhận phòng leaves no notification" do
    rooms(:limdim).bookings.create!(start_date: "2026-11-07", end_date: "2026-11-09", guest_name: "Anh Minh", checked_in_at: 1.day.ago)
    booking = rooms(:limdim).bookings.create!(start_date: "2026-11-20", end_date: "2026-11-22", guest_name: "Chị Hoa", price: 300_000)
    assert_no_difference -> { Notification.count } do
      assert_not booking.collecting_due(true) { booking.check_in } # Nhận phòng sớm while Anh Minh is still in
    end
    assert_empty booking.payments
  end

  test "pruned after the inbox window" do
    rooms(:limdim).bookings.create!(start_date: "2026-11-20", end_date: "2026-11-22")
    travel 32.days
    rooms(:limdim).bookings.create!(start_date: "2026-12-20", end_date: "2026-12-22")
    Notification.prune
    assert_equal 1, Notification.count
  end
end
