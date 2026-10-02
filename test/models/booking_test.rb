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
    assert_includes booking.errors[:base], "Phòng đã có người đặt trong khoảng ngày này"
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
end
