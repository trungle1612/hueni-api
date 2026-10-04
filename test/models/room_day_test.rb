require "test_helper"

# Fixtures: tomo has limdim (confirmed 1/10–3/10, Anh Minh, not checked in) and garden (no bookings).
class RoomDayTest < ActiveSupport::TestCase
  setup { travel_to Time.zone.local(2026, 10, 2, 9) }

  def day_of(room) = RoomDay.for([ room ]).first

  test "free, arriving and held" do
    assert_equal :free, day_of(rooms(:garden)).state
    assert_equal [ :arriving, bookings(:limdim_confirmed) ], day_of(rooms(:limdim)).then { [ it.state, it.booking ] }

    rooms(:garden).bookings.create!(start_date: "2026-10-02", end_date: "2026-10-03", status: "hold")
    assert_equal :held, day_of(rooms(:garden)).state
  end

  test "confirmed beats an overlapping hold" do
    Booking.new(room: rooms(:limdim), start_date: "2026-10-02", end_date: "2026-10-03", status: "hold").save!(validate: false)
    assert_equal bookings(:limdim_confirmed), day_of(rooms(:limdim)).booking
  end

  test "occupied, then leaving on end_date and while overdue" do
    bookings(:limdim_confirmed).update_columns(checked_in_at: 1.day.ago)
    assert_equal :occupied, day_of(rooms(:limdim)).state
    travel_to(Time.zone.local(2026, 10, 3, 9)) { assert_equal :leaving, day_of(rooms(:limdim)).state }
    travel_to(Time.zone.local(2026, 10, 5, 9)) { assert_equal :leaving, day_of(rooms(:limdim)).state }
  end

  test "turnover day shows the leaving guest and the next arrival" do
    leaving = rooms(:garden).bookings.create!(start_date: "2026-09-30", end_date: "2026-10-02")
    leaving.update_columns(checked_in_at: 2.days.ago)
    arriving = rooms(:garden).bookings.create!(start_date: "2026-10-02", end_date: "2026-10-04")
    day = day_of(rooms(:garden))
    assert_equal [ :leaving, leaving, arriving ], [ day.state, day.booking, day.next_booking ]
  end

  test "free room shows its next booking" do
    later = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06")
    assert_equal [ :free, nil, later ], day_of(rooms(:garden)).then { [ it.state, it.booking, it.next_booking ] }
  end

  test "early check-out leaves the room free; inactive rooms are off" do
    bookings(:limdim_confirmed).update_columns(checked_in_at: 1.day.ago, checked_out_at: 1.hour.ago)
    assert_equal :free, day_of(rooms(:limdim)).state

    rooms(:limdim).update!(active: false)
    assert_equal :off, day_of(rooms(:limdim)).state
  end

  test "one query for many rooms, bookings keep their room" do
    rooms = [ rooms(:limdim), rooms(:garden) ]
    days = assert_queries_count(1) { RoomDay.for(rooms) }
    assert_equal rooms, days.map(&:room)
    assert_no_queries { assert_equal "Limdim", days.first.booking.room.name }
  end

  test "a guest due yesterday is still Chờ khách until 06:00" do
    travel_to Time.zone.local(2026, 10, 3, 1) # Anh Minh: 1/10–3/10, not checked in
    assert_equal [ :arriving, bookings(:limdim_confirmed) ], day_of(rooms(:limdim)).then { [ it.state, it.booking ] }
    travel_to Time.zone.local(2026, 10, 3, 6)
    assert_equal :free, day_of(rooms(:limdim)).state
  end
end
