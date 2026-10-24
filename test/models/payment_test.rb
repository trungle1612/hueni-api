require "test_helper"

class PaymentTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12)
    # Thu 01/10 → Sun 04/10: Thu night 400k, Fri and Sat nights 500k.
    @booking = rooms(:garden).bookings.create!(start_date: "2026-10-01", end_date: "2026-10-04", price: 400_000, weekend_price: 500_000, guest_name: "Chị Mai")
  end

  test "room total counts weekend nights; payments and refunds make paid and due" do
    assert_equal 1_400_000, @booking.room_total
    assert @booking.awaiting_deposit?
    @booking.payments.create!(amount: "300k", payment_method: "cash")
    @booking.payments.create!(amount: 100_000, payment_method: "bank", kind: "refund")
    assert_equal [ 200_000, 1_200_000 ], [ @booking.paid, @booking.due ]
    assert_not @booking.awaiting_deposit?
    assert_nil Booking.new(room: rooms(:limdim), start_date: "2026-10-01", end_date: "2026-10-02").room_total # no price yet
  end

  test "never more than is due, never refund more than paid; cancelled bookings only refund; OTA bookings take nothing" do
    assert_equal [ "Số tiền không được lớn hơn số còn phải thu (1.400.000 ₫)" ], @booking.payments.create(amount: 1_400_001, payment_method: "cash").errors.full_messages
    assert @booking.payments.create(amount: 1_400_000, payment_method: "cash").persisted?
    assert_equal [ "Số tiền không được lớn hơn số đã thu (1.400.000 ₫)" ], @booking.payments.create(amount: 1_400_001, payment_method: "cash", kind: "refund").errors.full_messages

    @booking.update!(status: "cancelled", cancel_reason: "Khách huỷ")
    assert_includes @booking.payments.create(amount: 1, payment_method: "cash").errors[:base], "Đặt phòng đã huỷ, chỉ hoàn tiền được"
    assert @booking.payments.create(amount: 1_400_000, payment_method: "cash", kind: "refund").persisted?

    ota = bookings(:limdim_confirmed).tap { it.update_columns(source: "ical") }
    assert_includes ota.payments.create(amount: 1, payment_method: "cash").errors[:base], "Đặt phòng OTA thanh toán qua kênh OTA"
    assert_nil ota.due
  end

  test "Đã cọc on a new booking becomes its first payment, capped at the room total" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-10", end_date: "2026-10-11", price: 400_000, deposit: "200k", deposit_method: "bank")
    assert_equal [ 200_000, "bank", "Cọc" ], booking.payments.sole.then { [ it.amount, it.payment_method, it.note ] }

    too_much = rooms(:garden).bookings.create(start_date: "2026-10-12", end_date: "2026-10-13", price: 400_000, deposit: 500_000)
    assert_equal [ "Đã cọc không được lớn hơn tiền phòng (400.000 ₫)" ], too_much.errors.full_messages_for(:deposit)
  end
end
