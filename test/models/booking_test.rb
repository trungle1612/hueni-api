require "test_helper"

class BookingTest < ActiveSupport::TestCase
  def build(**attrs)
    Booking.new(room: rooms(:garden), start_date: "2026-10-01", end_date: "2026-10-03", **attrs)
  end

  test "defaults to confirmed manual booking" do
    booking = build
    assert booking.confirmed?
    assert booking.manual?
    assert booking.valid?
  end

  test "end_date must be after start_date" do
    booking = build(end_date: "2026-10-01")
    assert_not booking.valid?
    assert_includes booking.errors.attribute_names, :end_date
  end

  test "rejects unknown status and source" do
    booking = build(status: "pending", source: "phone")
    assert_not booking.valid?
    assert_includes booking.errors.attribute_names, :status
    assert_includes booking.errors.attribute_names, :source
  end

  test "db enforces date order" do
    assert_raises(ActiveRecord::StatementInvalid) { build(end_date: "2026-09-30").save(validate: false) }
  end

  test "db enforces status values" do
    booking = build.tap(&:save!)
    assert_raises(ActiveRecord::StatementInvalid) { booking.update_column(:status, "pending") }
  end

  test "db enforces source values" do
    booking = build.tap(&:save!)
    assert_raises(ActiveRecord::StatementInvalid) { booking.update_column(:source, "phone") }
  end

  test "db enforces unique uid per calendar feed" do
    build(source: "ical", calendar_feed: calendar_feeds(:limdim_airbnb), uid: "abc").save!
    assert_raises(ActiveRecord::RecordNotUnique) do
      build(source: "ical", calendar_feed: calendar_feeds(:limdim_airbnb), uid: "abc", start_date: "2026-11-01", end_date: "2026-11-02").save!
    end
  end

  test "db enforces room foreign key" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Booking.new(room_id: 0, start_date: "2026-10-01", end_date: "2026-10-02").save(validate: false)
    end
  end

  test "blocking_on includes holds and confirmed covering the date, end date exclusive" do
    hold = build(status: "hold").tap(&:save!)
    build(status: "cancelled").save!
    confirmed = bookings(:limdim_confirmed) # 2026-10-01..2026-10-03

    assert_equal [ confirmed, hold ].sort_by(&:id), Booking.blocking_on(Date.new(2026, 10, 1)).order(:id).to_a
    assert_equal 2, Booking.blocking_on(Date.new(2026, 10, 2)).count
    assert_empty Booking.blocking_on(Date.new(2026, 10, 3)) # checkout day is free
    assert_empty Booking.blocking_on(Date.new(2026, 9, 30))
  end

  test "manual booking cannot overlap a blocking booking on the same room" do
    booking = build(room: rooms(:limdim), start_date: "2026-10-02", end_date: "2026-10-04", status: "hold") # limdim_confirmed: 10-01..10-03
    assert_not booking.valid?
    assert_includes booking.errors[:base], "Trùng lịch đêm 02/10 với Anh Minh (01/10–03/10). Đổi ngày hoặc huỷ đặt phòng bị trùng."
  end

  test "the overlap message names every night in common and counts other conflicts" do
    Booking.new(room: rooms(:limdim), start_date: "2026-10-03", end_date: "2026-10-04", note: "Giữ cho đoàn").save!(validate: false)
    booking = build(room: rooms(:limdim), start_date: "2026-09-30", end_date: "2026-10-05")
    assert_not booking.valid?
    assert_equal [ "Trùng lịch đêm 01/10–02/10 với Anh Minh (01/10–03/10) và 1 đặt phòng khác. Đổi ngày hoặc huỷ đặt phòng bị trùng." ],
      booking.errors[:base]
  end

  test "overlap ignores touching dates, other rooms, cancelled bookings and itself" do
    assert build(room: rooms(:limdim), start_date: "2026-10-03", end_date: "2026-10-05").valid? # checkout day is free
    assert build(room: rooms(:limdim), start_date: "2026-09-29", end_date: "2026-10-01").valid?
    assert build(start_date: "2026-10-01", end_date: "2026-10-03").valid? # garden
    assert build(room: rooms(:limdim), status: "cancelled").valid?
    assert bookings(:limdim_confirmed).valid?

    bookings(:limdim_confirmed).update!(status: "cancelled")
    assert build(room: rooms(:limdim)).valid?
  end

  test "manual booking cannot overlap an iCal booking, but iCal bookings skip the check" do
    build(room: rooms(:limdim), start_date: "2026-10-05", end_date: "2026-10-07", source: "ical",
      calendar_feed: calendar_feeds(:limdim_airbnb), uid: "a").save!
    assert_not build(room: rooms(:limdim), start_date: "2026-10-06", end_date: "2026-10-08").valid?

    ical = build(room: rooms(:limdim), source: "ical", calendar_feed: calendar_feeds(:limdim_airbnb), uid: "b")
    assert ical.valid? # overlaps limdim_confirmed: the OTA already sold the nights
  end

  test "guests is optional and must fit the room" do
    assert build(guests: nil).valid?
    assert build(guests: 2).valid?
    [ 0, 3 ].each do |guests|
      booking = build(guests:)
      assert_not booking.valid?
      assert_includes booking.errors[:base], "Số khách phải từ 1 đến 2"
    end
  end

  test "a checked-in booking cannot be cancelled" do
    booking = build.tap(&:save!)
    booking.update_column(:checked_in_at, Time.current)
    assert_not booking.update(status: "cancelled")
    assert_includes booking.errors[:base], "Khách đã nhận phòng, không huỷ được"
  end

  test "update_with_status moves through every allowed status event" do
    booking = build(status: "hold").tap(&:save!)
    { "confirmed" => :confirmed, "hold" => :hold, "cancelled" => :cancelled }.each do |to, expected|
      assert booking.update_with_status(status: to)
      assert_equal expected, booking.reload.aasm.current_state
    end
    assert booking.update_with_status(status: "confirmed", note: "Khách quay lại")
    assert_equal [ "confirmed", "Khách quay lại" ], booking.reload.values_at(:status, :note)
  end

  test "update_with_status keeps a refused change unsaved" do
    booking = build.tap(&:save!)
    booking.update_column(:checked_in_at, Time.current)
    assert_not booking.update_with_status(status: "cancelled", note: "x")
    assert_includes booking.errors[:base], "Khách đã nhận phòng, không huỷ được"
    assert_equal [ "confirmed", nil ], booking.reload.values_at(:status, :note)
  end

  test "db rejects check-out without check-in" do
    booking = build.tap(&:save!)
    assert_raises(ActiveRecord::StatementInvalid) { booking.update_column(:checked_out_at, Time.current) }
  end

  test "in_house and not_checked_in scopes" do
    waiting = build.tap(&:save!)
    staying = build(room: rooms(:limdim), start_date: "2026-10-05", end_date: "2026-10-06").tap(&:save!)
    staying.update_column(:checked_in_at, Time.current)
    gone = build(start_date: "2026-10-05", end_date: "2026-10-06").tap(&:save!)
    gone.update_columns(checked_in_at: Time.current, checked_out_at: Time.current)

    assert_equal [ staying ], Booking.in_house.to_a
    assert_includes Booking.not_checked_in, waiting
    assert_not_includes Booking.not_checked_in, staying
  end

  test "no-show cancels a late manual booking and notes it" do
    booking = saved(room: rooms(:garden), start_date: "2026-10-01", end_date: "2026-10-04", note: "Đặt qua Zalo")
    travel_to Time.zone.local(2026, 10, 2, 9) do
      assert booking.can_no_show?
      assert booking.no_show
    end
    booking.reload
    assert booking.cancelled?
    assert_equal "Đặt qua Zalo · Không đến", booking.note
  end

  test "no-show is refused unless the guest is late, the booking manual and not checked in" do
    travel_to Time.zone.local(2026, 10, 2, 9) do
      today = saved(room: rooms(:garden), start_date: "2026-10-02", end_date: "2026-10-03")
      assert_refused today, :no_show, "Chưa qua ngày nhận phòng"

      ical = calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:garden), uid: "x", start_date: "2026-10-01", end_date: "2026-10-02", source: "ical")
      assert_refused ical, :no_show, "Đặt phòng OTA: huỷ trên Airbnb / Booking.com"

      booking = bookings(:limdim_confirmed) # 1/10–3/10
      booking.update_columns(checked_in_at: 1.day.ago)
      assert_refused booking, :no_show, "Khách đã nhận phòng rồi"
      assert_not booking.reload.cancelled?

      booking.update_columns(checked_in_at: nil, status: "cancelled")
      assert_refused booking, :no_show, "Đặt phòng đã huỷ"
    end
  end
  def saved(**attrs) = build(**attrs).tap(&:save!)

  def assert_refused(booking, action, message)
    assert_not booking.public_send(action)
    assert_includes booking.errors[:base], message
  end

  test "check-in is allowed from start_date until the day before end_date" do
    booking = saved(status: "hold")
    travel_to Time.zone.local(2026, 10, 2, 23, 30) do
      assert booking.can_check_in?
      assert booking.check_in
    end
    booking.reload
    assert_equal Time.zone.local(2026, 10, 2, 23, 30), booking.checked_in_at
    assert booking.confirmed?, "a hold becomes confirmed when the guest arrives"
  end

  test "a late guest can still check in on end_date until LATE_ARRIVAL_UNTIL (Huế time)" do
    booking = saved
    travel_to Time.utc(2026, 10, 2, 17, 30) do # 00:30 on 3/10 in Huế
      assert_not booking.early_check_in?
      assert booking.check_in, booking.errors.full_messages.to_sentence
      assert booking.can_check_out?
    end
    assert_equal [ Date.new(2026, 10, 1), Date.new(2026, 10, 3) ], booking.reload.values_at(:start_date, :end_date)
  end

  test "check-in is refused from LATE_ARRIVAL_UNTIL on end_date, when cancelled or twice" do
    booking = saved
    travel_to(Time.zone.local(2026, 10, 3, Booking::LATE_ARRIVAL_UNTIL)) { assert_refused booking, :check_in, "Đặt phòng đã kết thúc" }

    travel_to Time.zone.local(2026, 10, 1, 12) do
      assert booking.check_in
      assert_refused booking, :check_in, "Khách đã nhận phòng rồi"
    end

    cancelled = saved(start_date: "2026-10-05", end_date: "2026-10-06", status: "cancelled")
    travel_to(Time.zone.local(2026, 10, 5, 12)) { assert_refused cancelled, :check_in, "Đặt phòng đã huỷ" }
  end

  test "check-in records the arrival even when the booking no longer validates" do
    booking = saved(guests: 2, status: "hold")
    rooms(:garden).update!(max_guests: 1)
    travel_to Time.zone.local(2026, 10, 1, 12) do
      assert booking.check_in, booking.errors.full_messages.to_sentence
    end
    assert booking.reload.checked_in_at
    assert booking.confirmed?
  end

  test "check-in of a manual booking overlapping an iCal one succeeds and is logged" do
    manual = bookings(:limdim_confirmed) # 1/10–3/10
    calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:limdim), uid: "x", start_date: "2026-10-02", end_date: "2026-10-04", source: "ical")
    assert_not manual.valid?
    travel_to Time.zone.local(2026, 10, 1, 14) do
      assert manual.check_in, manual.errors.full_messages.to_sentence
    end
    assert manual.reload.checked_in_at
    assert_includes manual.versions.reorder(:id).last.changeset.keys, "checked_in_at"
  end

  test "check-out sets the time and marks the room dirty" do
    booking = saved
    travel_to Time.zone.local(2026, 10, 1, 12) do
      assert_refused booking, :check_out, "Khách chưa nhận phòng"
      assert_not booking.can_check_out?
      booking.check_in
      assert booking.can_check_out?
    end
    travel_to Time.zone.local(2026, 10, 3, 10) do
      assert booking.check_out
      assert_refused booking, :check_out, "Khách đã trả phòng rồi"
    end
    assert_equal Time.zone.local(2026, 10, 3, 10), booking.reload.checked_out_at
    assert rooms(:garden).reload.dirty?
  end

  test "check-out works even when the booking no longer validates" do
    booking = saved(room: rooms(:limdim), start_date: "2026-10-05", end_date: "2026-10-08", guests: 4)
    travel_to(Time.zone.local(2026, 10, 5, 12)) { booking.check_in }
    rooms(:limdim).update!(max_guests: 2)
    calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:limdim), uid: "late@airbnb", start_date: "2026-10-07", end_date: "2026-10-09", source: "ical")

    travel_to Time.zone.local(2026, 10, 6, 10) do
      assert booking.check_out, booking.errors.full_messages.to_sentence
    end
    assert booking.reload.checked_out_at
    assert rooms(:limdim).reload.dirty?
  end

  test "a checked-out booking stops blocking from its check-out day; its dates stay" do
    booking = saved(start_date: "2026-10-01", end_date: "2026-10-04") # garden, 3 nights
    travel_to(Time.zone.local(2026, 10, 1, 14)) { booking.check_in }
    travel_to(Time.utc(2026, 10, 1, 17, 30)) { booking.check_out } # 00:30 on 2/10 in Huế: left after one night

    assert_equal [ Date.new(2026, 10, 1), Date.new(2026, 10, 4) ], booking.reload.values_at(:start_date, :end_date)
    assert_equal Date.new(2026, 10, 2), booking.occupied_until
    assert_includes Booking.blocking_on(Date.new(2026, 10, 1)), booking
    assert_not_includes Booking.blocking_on(Date.new(2026, 10, 2)), booking
    assert_not_includes Booking.blocking_on(Date.new(2026, 10, 3)), booking

    assert saved(start_date: "2026-10-02", end_date: "2026-10-05").persisted?
    assert_not build(start_date: "2026-09-30", end_date: "2026-10-02").valid? # 1/10 is still held
    booking.update!(note: "Về sớm") # still saves next to the new booking
  end

  test "checked out on the arrival day frees that night too" do
    booking = saved(start_date: "2026-10-01", end_date: "2026-10-02")
    travel_to Time.zone.local(2026, 10, 1, 15) do
      booking.check_in
      booking.check_out
    end
    assert_empty Booking.blocking_on(Date.new(2026, 10, 1)).where(id: booking.id)
    assert saved(start_date: "2026-10-01", end_date: "2026-10-02").persisted?
    booking.update!(note: "Ở 1 tiếng")
  end

  test "early check-in moves start_date to today and is logged" do
    booking = saved(start_date: "2026-10-05", end_date: "2026-10-07", status: "hold")
    travel_to Time.zone.local(2026, 10, 3, 21) do
      assert booking.early_check_in?
      assert booking.can_check_in?
      assert booking.check_in
    end
    booking.reload
    assert_equal Date.new(2026, 10, 3), booking.start_date
    assert booking.confirmed?
    assert_equal Time.zone.local(2026, 10, 3, 21), booking.checked_in_at
    assert_equal %w[2026-10-05 2026-10-03], booking.versions.reorder(:id).last.changeset["start_date"]
  end

  test "early check-in is refused when the room is not free from today, or for iCal" do
    saved(start_date: "2026-10-03", end_date: "2026-10-04", guest_name: "Đang ở")
    booking = saved(start_date: "2026-10-04", end_date: "2026-10-06")
    travel_to(Time.zone.local(2026, 10, 2, 12)) { assert_refused booking, :check_in, "Phòng chưa trống từ hôm nay" }
    assert_equal Date.new(2026, 10, 4), booking.reload.start_date

    ical = calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:limdim), uid: "x", start_date: "2026-10-10", end_date: "2026-10-12", source: "ical")
    travel_to(Time.zone.local(2026, 10, 5, 12)) { assert_refused ical, :check_in, "Đặt phòng OTA: đổi ngày trên Airbnb / Booking.com" }
  end

  test "iCal conflicts ignore the nights after a manual guest checked out" do
    manual = bookings(:limdim_confirmed) # 1/10–3/10
    travel_to(Time.zone.local(2026, 10, 1, 14)) { manual.check_in }
    ical = calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:limdim), uid: "x", start_date: "2026-10-02", end_date: "2026-10-03", source: "ical")
    assert manual.overlaps?(ical)
    travel_to(Time.zone.local(2026, 10, 2, 9)) { manual.check_out }
    assert_not manual.overlaps?(ical)
  end

  test "a guest still in after the departure day keeps the room occupied until checked out" do
    booking = saved(start_date: "2026-10-01", end_date: "2026-10-03")
    travel_to(Time.zone.local(2026, 10, 1, 14)) { booking.check_in }

    travel_to Time.zone.local(2026, 10, 3, 20) do # departure day: tonight is still sellable
      assert_not_includes Booking.blocking_on(Date.current), booking
      assert build(start_date: "2026-10-03", end_date: "2026-10-04").valid?
    end

    travel_to Time.zone.local(2026, 10, 5, 9) do # two days late
      assert_includes Booking.blocking_on(Date.current), booking
      assert_not_includes Booking.blocking_on(Date.current.next_day), booking
      assert_equal Date.new(2026, 10, 6), booking.occupied_until
      assert_not build(start_date: "2026-10-05", end_date: "2026-10-06").valid?
      booking.check_out
      assert_not_includes Booking.blocking_on(Date.current), booking
    end
  end

  test "check-in is refused while another guest is still in the room" do
    staying = saved(start_date: "2026-10-01", end_date: "2026-10-02")
    arriving = saved(start_date: "2026-10-02", end_date: "2026-10-04")
    travel_to(Time.zone.local(2026, 10, 1, 14)) { staying.check_in }
    travel_to Time.zone.local(2026, 10, 2, 12) do
      assert_refused arriving, :check_in, "Phòng đang có khách chưa trả phòng"
      staying.check_out
      assert arriving.reload.check_in
    end
  end
end
