## Rails 8 backend for hueni.me — the Huế travel guide.

- Vacancy API — GET /v1/vacancy returns free homestay rooms today, used by hueni's "Phòng trống" tab.
- Owner admin — homestay owners manage rooms, calendar feeds, and manual bookings at /admin.
- iCal sync — hourly import of bookings from Airbnb / Booking.com calendars.

## Stack

- Rails 8 · Ruby 3.4 · SQLite · Solid Queue/Cache/Cable · Hotwire · Kamal 2 · Litestream
