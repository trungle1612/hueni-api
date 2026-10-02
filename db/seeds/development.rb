# Made-up demo data for local development. Safe to re-run: rooms and feeds are reused, and the demo
# bookings are recreated relative to today so the calendar and /v1/vacancy always have something to show.
#
#   bin/rails db:seed
#
# Logins (password "password123"): 0900 000 001 (admin, sees everything), 0900 000 002 (owner of 3 homestays).

# db/places/*.json is git-ignored (copied from hue-ni), so a fresh clone may have no places: make some up.
if Place.none?
  [ [ "demo-song-huong", "Demo Sông Hương" ], [ "demo-kim-long", "Demo Kim Long" ], [ "demo-vy-da", "Demo Vỹ Dạ" ] ].each do |slug, name|
    Place.create!(slug:, name:, address: "Huế, Việt Nam")
  end
end
places = Place.order(:name).first(3)

User.find_or_create_by!(phone_number: "0900000001") { it.assign_attributes(name: "Quản trị", role: "admin", password: "password123") }
owner = User.find_or_create_by!(phone_number: "0900000002") { it.assign_attributes(name: "Chị Hoa", role: "owner", password: "password123") }
places.each { |place| owner.place_memberships.find_or_create_by!(place:) }

ROOMS = [
  [ "Sen", 2, 350_000 ], [ "Cúc", 2, 300_000 ], [ "Lan", 4, 550_000 ], [ "Đào", 3, 450_000 ], [ "Mai", 6, 800_000 ]
].freeze
GUESTS = [ "Anh Minh", "Chị Mai", "Anh Tuấn", "Chị Thảo", "Anh Khoa", "Chị Ngọc", "Anh Long", "Chị Vy" ].freeze

today = Date.current
places.each_with_index do |place, place_index|
  rooms = ROOMS.first(3 + place_index).map do |name, max_guests, price|
    place.rooms.find_or_create_by!(name:) { it.assign_attributes(max_guests:, price:, active: true) }
  end
  Booking.where(room: rooms).delete_all # also removes old iCal rows; feeds below re-add theirs

  # Manual bookings: a past stay, today's guests, holds, a cancellation, something next week.
  rooms.each_with_index do |room, i|
    offset = i * 2 + place_index
    guest = GUESTS[(i + place_index) % GUESTS.size]
    room.bookings.create!(start_date: today - 6 + i, end_date: today - 3 + i, status: "confirmed", guest_name: "Khách cũ #{i + 1}")
    room.bookings.create!(start_date: today + offset - 1, end_date: today + offset + 1, status: i.odd? ? "hold" : "confirmed",
      guest_name: guest, guest_phone: "0905 #{100 + i}#{place_index} #{456 + offset}", note: ("Đến muộn" if i == 1))
    room.bookings.create!(start_date: today + offset + 3, end_date: today + offset + 4, status: "cancelled", guest_name: "Khách huỷ", note: "Đổi kế hoạch")
    room.bookings.create!(start_date: today + 8 + i, end_date: today + 10 + i, status: "hold", note: "Giữ cho đoàn")
  end

  # OTA feeds: one healthy, one failing. URLs are fake, so validation (DNS) is skipped and "Đồng bộ ngay" will just record an error.
  airbnb = CalendarFeed.find_or_initialize_by(room: rooms.first, provider: "airbnb")
  airbnb.url ||= "https://www.airbnb.com/calendar/ical/demo-#{place.id}.ics?s=demo-token"
  airbnb.assign_attributes(last_synced_at: 20.minutes.ago, last_error: nil, last_error_at: nil)
  airbnb.save!(validate: false)
  # Overlaps the first room's manual booking around today on purpose: shows as a conflict on the calendar.
  airbnb.bookings.create!(room: rooms.first, uid: "demo-#{place.id}-1@airbnb.com", source: "ical", start_date: today + place_index, end_date: today + place_index + 3)
  airbnb.bookings.create!(room: rooms.first, uid: "demo-#{place.id}-2@airbnb.com", source: "ical", start_date: today + 12, end_date: today + 15)

  booking = CalendarFeed.find_or_initialize_by(room: rooms.second, provider: "booking")
  booking.url ||= "https://admin.booking.com/hotel/hoteladmin/ical.html?t=demo-#{place.id}"
  booking.assign_attributes(last_synced_at: 1.day.ago, last_error: "RuntimeError: HTTP 404", last_error_at: 2.hours.ago)
  booking.save!(validate: false)
  booking.bookings.create!(room: rooms.second, uid: "demo-#{place.id}-3@booking.com", source: "ical", start_date: today + 5, end_date: today + 7)
end

Vacancy.bust
puts "Seeded #{places.map(&:name).join(", ")}: #{Room.count} rooms, #{Booking.count} bookings, #{CalendarFeed.count} feeds."
puts "Log in at /session/new as 0900 000 002 (owner) or 0900 000 001 (admin), password password123."
