require "test_helper"

# Trang đặt phòng riêng (#172): online requests, holds and their expiry.
class BookingSiteTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12) # limdim booked 01–03/10 by Anh Minh
    rooms(:garden).update!(room_type: "double", price: 400_000)
    rooms(:limdim).update!(room_type: "double", price: 500_000)
    @place = places(:tomo)
    @place.update!(bank_name: "Vietcombank", bank_account: "0123456789", bank_holder: "NGUYEN THI LAN", site_open: true)
  end

  def request(**attrs) = @place.book_online(room_type: "double", start_date: "2026-10-01", end_date: "2026-10-02", guests: 2, guest_name: "Chị Hoa", guest_phone: "0905 111 333", **attrs)

  test "takes the first free room of the type by name and holds it for the hold time, deposit rounded up" do
    booking = request
    assert booking.persisted?
    assert_equal [ rooms(:garden), true, Time.zone.local(2026, 10, 1, 12, 30) ], [ booking.room, booking.online, booking.hold_expires_at ]
    assert_equal 120_000, booking.site_deposit
    assert booking.held?

    @place.update!(site_deposit_percent: 0)
    second = request(start_date: "2026-10-03", end_date: "2026-10-04", guest_name: "Anh Tú")
    assert_equal [ rooms(:garden), nil, 0 ], [ second.room, second.hold_expires_at, second.site_deposit ]
  end

  test "a full type says so without naming the booking in the way" do
    request
    full = request(guest_name: "Anh Tú")
    assert_not full.persisted?
    assert_equal [ Place::SITE_FULL ], full.errors.full_messages
    assert_no_match "Anh Minh", full.errors.full_messages.join
  end

  test "refuses a closed page, hidden or unknown types, past days, after the cutoff, long stays and missing guest fields" do
    assert_includes request(guests: 5).errors[:guests], "nhiều hơn sức chứa của loại phòng này"
    assert_includes request(start_date: "2026-09-30").errors[:start_date], "đã qua"
    assert_includes request(end_date: "2026-11-15").errors[:end_date], "tối đa 30 đêm"
    assert request(guest_name: "", guest_phone: "12").errors.attribute_names.to_set >= Set[:guest_name, :guest_phone]
    assert request(room_type: "villa").errors[:base].any?
    travel_to Time.zone.local(2026, 10, 1, 20, 5) do
      assert_includes request.errors[:start_date], "hôm nay chỉ nhận đặt đến 20:00"
    end
    @place.update!(site_open: false)
    assert_equal [ "Homestay đang tạm ngưng nhận đặt phòng online" ], request.errors[:base]
    assert_equal 0, Booking.where(online: true).count
  end

  test "an unpaid hold is cancelled once it expires; money in or a check-in ends the hold" do
    unpaid = request
    paid = request(start_date: "2026-10-05", end_date: "2026-10-06")
    paid.payments.create!(amount: 120_000, payment_method: "bank")
    assert_nil paid.reload.hold_expires_at

    travel 31.minutes
    Booking.expire_holds
    assert_equal [ "cancelled", Booking::HOLD_EXPIRED_REASON ], unpaid.reload.values_at(:status, :cancel_reason)
    assert paid.reload.confirmed?
    assert request.persisted?, "the room is free again"
  end

  test "opening the page needs a room type shown and, with a deposit, a bank account" do
    @place.site_hidden_room_types = [ "double" ]
    assert_not @place.valid?
    @place.site_hidden_room_types = [ "bogus" ]
    assert_not @place.valid?
    @place.assign_attributes(site_hidden_room_types: [], bank_account: nil)
    assert_includes @place.tap(&:validate).errors[:site_open], "cần tài khoản chuyển khoản để nhận cọc"
    @place.site_deposit_percent = 0
    assert @place.valid?
  end
end
