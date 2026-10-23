# Made-up demo data for local development. Safe to re-run: rooms and feeds are reused, and the demo
# bookings are recreated relative to today so the calendar and /v1/vacancy always have something to show.
#
#   bin/rails db:seed
#
# Logins: 0900 000 001 / password123 (admin: accounts only, member of nothing). Owner (3 homestays) and staff (first
# homestay) have fake Zalo ids: log in as them with ZALO_FAKE=1 bin/dev (config/initializers/omniauth.rb).

# db/places/*.json is git-ignored (copied from hue-ni), so a fresh clone may have no places: make some up.
if Place.none?
  [ [ "demo-song-huong", "Demo Sông Hương" ], [ "demo-kim-long", "Demo Kim Long" ], [ "demo-vy-da", "Demo Vỹ Dạ" ] ].each do |slug, name|
    Place.create!(slug:, name:, address: "Huế, Việt Nam")
  end
end
places = Place.order(:name).first(3)

User.find_or_create_by!(phone_number: "0900000001") { it.assign_attributes(name: "Quản trị", role: "admin", password: "password123") }
owner = User.find_or_create_by!(phone_number: "0900000002") { it.assign_attributes(name: "Chị Hoa", role: "user", password: "password123") }
owner.update!(zalo_id: "dev-zalo-owner")
places.each { |place| owner.place_memberships.find_or_create_by!(place:) }
staff = User.find_or_create_by!(phone_number: "0900000003") { it.assign_attributes(name: "Em Hằng", role: "user", password: "password123") }
staff.update!(zalo_id: "dev-zalo-staff")
staff.place_memberships.find_or_create_by!(place: places.first) { it.role = "staff" }

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

  # Manual bookings: a past stay, today's guests (some with a deposit), a cancellation, something next week.
  rooms.each_with_index do |room, i|
    offset = i * 2 + place_index
    guest = GUESTS[(i + place_index) % GUESTS.size]
    room.bookings.create!(start_date: today - 6 + i, end_date: today - 3 + i, status: "confirmed", guest_name: "Khách cũ #{i + 1}")
    room.bookings.create!(start_date: today + offset - 1, end_date: today + offset + 1, status: "confirmed", deposit: (200_000 if i.even?),
      guest_name: guest, guest_phone: "0905 #{100 + i}#{place_index} #{456 + offset}", note: ("Đến muộn" if i == 1))
    room.bookings.create!(start_date: today + offset + 3, end_date: today + offset + 4, status: "cancelled", guest_name: "Khách huỷ", note: "Đổi kế hoạch")
    room.bookings.create!(start_date: today + 8 + i, end_date: today + 10 + i, status: "confirmed", note: "Đoàn")
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

# Sync history (admin → Đồng bộ): the last 3 days of hourly runs for every demo feed, recreated on each seed.
# Airbnb feeds mostly "no change" with the odd new or moved booking; Booking.com feeds fail for the last 2 hours
# (matching their last_error above). Plus one "Đồng bộ ngay" and one "Thêm kênh".
feeds = CalendarFeed.where(room: Room.where(place: places)).order(:id).to_a
SyncRun.where(calendar_feed: feeds).delete_all
random = Random.new(92)
now = Time.current
runs = (0...72).to_a.reverse.flat_map do |hours_ago|
  hour = (now - hours_ago.hours).beginning_of_hour
  feeds.each_with_index.map do |feed, i|
    started_at = hour + i * 2 + random.rand(0.0..1.0)
    failing = feed.booking? && hours_ago < 2
    changes = !failing && random.rand < 0.15
    { calendar_feed_id: feed.id, trigger: "hourly", ok: !failing, error: (feed.last_error if failing),
      created_count: changes ? random.rand(0..2) : 0, updated_count: changes ? random.rand(0..1) : 0, removed_count: changes && random.rand < 0.3 ? 1 : 0,
      started_at:, finished_at: started_at + random.rand(0.3..(failing ? 15.0 : 2.5)) }
  end
end
manual = (now - 25.minutes).change(usec: 0)
runs << { calendar_feed_id: feeds.first.id, trigger: "manual", ok: true, error: nil, created_count: 1, updated_count: 0, removed_count: 0, started_at: manual, finished_at: manual + 1.2 }
added = (now - 2.days).beginning_of_hour + 40.minutes
runs << { calendar_feed_id: feeds.last.id, trigger: "added", ok: true, error: nil, created_count: 2, updated_count: 0, removed_count: 0, started_at: added, finished_at: added + 1.8 }
SyncRun.insert_all!(runs.sort_by { it[:started_at] }) # ids follow time, like real runs

Vacancy.bust
puts "Seeded #{places.map(&:name).join(", ")}: #{Room.count} rooms, #{Booking.count} bookings, #{CalendarFeed.count} feeds, #{SyncRun.count} sync runs."
puts "Log in at /session/new as 0900 000 001 / password123 (admin), with real Zalo, or (ZALO_FAKE=1 bin/dev) fake Zalo as Chị Hoa / Em Hằng."
