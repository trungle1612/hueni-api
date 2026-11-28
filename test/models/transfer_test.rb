require "test_helper"

# Đưa đón sân bay (#306): legs asked with a booking request, refused for non-partners, following request and booking.
class TransferTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12)
    rooms(:garden).update!(room_type: "double", price: 400_000)
    @place = places(:tomo)
    site_ready(@place)
    @place.update!(site_open: true, transfer_partner: true)
  end

  def ask(transfer = { arrival: { time: "14:30", flight: "vj 123" }, departure: true }, **attrs)
    @place.book_online(room_type: "double", start_date: "2026-10-05", end_date: "2026-10-07", guests: 2, guest_name: "Chị Hoa", guest_phone: "0905 111 333", transfer:, **attrs)
  end

  test "a non-partner refuses a transfer; without one nothing changes" do
    @place.update!(transfer_partner: false)
    refused = ask
    assert_not refused.persisted?
    assert_equal [ Place::TRANSFER_REFUSED ], refused.errors.full_messages
    assert ask(nil).persisted?
    assert_equal 0, Transfer.count
  end

  test "a partner request creates pending legs on the stay's dates at the place price" do
    request = ask
    assert_equal [ [ "arrival", Date.new(2026, 10, 5), "14:30", "VJ 123", "pending", 200_000 ], [ "departure", Date.new(2026, 10, 7), nil, nil, "pending", 200_000 ] ],
      request.transfers.order(:id).map { [ it.kind, it.date, it.pickup_time, it.flight, it.status, it.price ] }
  end

  test "an arrival needs a valid time; nothing is saved" do
    bad = ask({ arrival: { time: "" } })
    assert_not bad.persisted?
    assert_equal [ "Cần giờ máy bay đến để đón đúng giờ" ], bad.errors.full_messages
    assert_not ask({ arrival: { time: "25:00" } }).persisted?
    assert_equal [ 0, 0 ], [ Transfer.count, BookingRequest.count ]
  end

  test "driver phone is kept as 10 digits" do
    @place.update!(driver_phone: "+84 912 345 678")
    assert_equal "0912345678", @place.driver_phone
  end

  test "decline and expiry cancel the legs; undo of a decline brings them back" do
    declined = ask
    assert declined.decline(reason: "full")
    assert_equal [ "cancelled" ], declined.transfers.map(&:status).uniq
    assert declined.undo
    assert_equal [ "pending" ], declined.transfers.reload.map(&:status).uniq

    expiring = ask(guest_name: "Anh Tú", start_date: "2026-10-10", end_date: "2026-10-12")
    travel 31.minutes
    BookingRequest.expire
    assert_equal [ "cancelled" ], expiring.transfers.reload.map(&:status).uniq
  end

  test "accepted legs follow the booking: dates move, cancel cancels" do
    request = ask
    assert request.accept(room: rooms(:garden), deposit_percent: 0)
    booking = request.reload.booking
    assert_equal [ booking.id ], request.transfers.pluck(:booking_id).uniq
    booking.update!(end_date: "2026-10-08")
    assert_equal [ Date.new(2026, 10, 5), Date.new(2026, 10, 8) ], booking.transfers.order(:id).pluck(:date)
    booking.cancel_reason = "Khách huỷ"
    booking.cancel!
    assert_equal [ "cancelled" ], booking.transfers.reload.map(&:status).uniq
    booking.reopen!
    assert_equal [ "pending" ], booking.transfers.reload.map(&:status).uniq
  end

  test "an arrival whose day moves is cancelled, the departure stays" do
    request = ask
    request.accept(room: rooms(:garden), deposit_percent: 0)
    booking = request.reload.booking
    booking.update!(start_date: "2026-10-04")
    assert_equal [ [ "arrival", "cancelled" ], [ "departure", "pending" ] ], booking.transfers.order(:id).map { [ it.kind, it.status ] }
  end

  test "auto mode books and attaches the legs to the booking" do
    @place.update!(site_mode: "auto")
    booking = ask
    assert booking.persisted?
    assert_equal %w[arrival departure], booking.transfers.order(:id).map(&:kind)
  end
end
