require "test_helper"

# Fixtures: tomo has limdim (4 guests, confirmed 2026-10-01..03) and garden (2 guests); hiuhill has no rooms.
class VacancyTest < ActiveSupport::TestCase
  def book(room, start_date, end_date, status: "confirmed")
    Booking.create!(room: rooms(room), start_date:, end_date:, status:)
  end

  test "booking starting today makes the room booked" do
    assert_equal({ "tomo-homestay" => { left: 1, max_guests: 2 } }, Vacancy.on(Date.new(2026, 10, 1)))
  end

  test "booking ending today leaves the room free" do
    assert_equal({ left: 2, max_guests: 4 }, Vacancy.on(Date.new(2026, 10, 3))["tomo-homestay"])
  end

  test "hold makes the room booked" do
    book(:garden, "2026-10-01", "2026-10-02", status: "hold")
    assert_equal({ left: 0, max_guests: 0 }, Vacancy.on(Date.new(2026, 10, 1))["tomo-homestay"])
  end

  test "cancelled booking leaves the room free" do
    book(:garden, "2026-10-01", "2026-10-02", status: "cancelled")
    assert_equal({ left: 1, max_guests: 2 }, Vacancy.on(Date.new(2026, 10, 1))["tomo-homestay"])
  end

  test "inactive rooms are excluded" do
    rooms(:limdim).update!(active: false)
    assert_equal({ left: 1, max_guests: 2 }, Vacancy.on(Date.new(2026, 10, 5))["tomo-homestay"])
  end

  test "places without active rooms are omitted" do
    Room.create!(place: places(:hiuhill), name: "Old", max_guests: 2, active: false)
    assert_not Vacancy.on(Date.new(2026, 10, 5)).key?("hiuhill-homestay")
  end

  test "defaults to today in Huế, which starts at 17:00 UTC" do
    travel_to Time.utc(2026, 10, 2, 16, 59) do # 23:59 on Oct 2 in Huế
      assert_equal 1, Vacancy.on["tomo-homestay"][:left]
    end
    travel_to Time.utc(2026, 10, 2, 17, 0) do # 00:00 on Oct 3 in Huế, limdim checkout day
      assert_equal 2, Vacancy.on["tomo-homestay"][:left]
    end
  end

  test "a guest who checked out frees the room for the rest of the stay" do
    booking = bookings(:limdim_confirmed) # 1/10–3/10
    travel_to(Time.zone.local(2026, 10, 1, 14)) { booking.check_in }
    travel_to(Time.zone.local(2026, 10, 2, 9)) { booking.check_out }
    assert_equal({ left: 2, max_guests: 4 }, Vacancy.on(Date.new(2026, 10, 2))["tomo-homestay"])
  end
end
