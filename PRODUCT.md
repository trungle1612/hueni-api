# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Homestay owners in Huế** — Vietnamese-speaking, mostly on phones, often older and not comfortable with software. They set up rooms, prices and OTA calendar feeds, and read the monthly report.
- **Front-desk staff** — same profile; do daily work on a phone at the desk: check-in/out, room moves, cleaning, lưu trú declarations. No access to prices or owner-only settings.
- **Admins (hueni team)** — run accounts and memberships, watch failing feeds and the sync log. They do not operate homestays unless added as a member.
- **hueni.me visitors** — never see the admin; they consume `GET /v1/vacancy` through hueni's "Phòng trống" tab.

## Product Purpose

Backend + owner admin for hueni.me, a travel guide for Huế. Owners keep one accurate picture of which rooms are free; hueni.me publishes today's free rooms. Success: an owner answers "which rooms are free, who arrives/leaves today, what needs cleaning" in seconds on a phone, and their vacancy on hueni.me is always correct.

## Positioning

**Free listing traffic.** Keeping room status accurate here is what puts a homestay's free rooms on hueni.me in front of travellers planning a Huế trip — direct guests without OTA commission. The admin (calendar, iCal sync from Airbnb / Booking.com, front-desk board) exists so that vacancy stays true with minimal effort.

## Operating Context

- Small family homestays, a handful of rooms each; bookings arrive from Airbnb, Booking.com (via iCal) and directly (phone/Zalo, entered by hand).
- Daily rhythm: Hôm nay board → arrivals, departures, in-house guests, dirty rooms; late arrivals after midnight count for the previous day until 06:00.
- Legal lưu trú (residence) declaration per guest; the app only reminds, it does not submit.
- Accounts are created by admins; setup links are sent over Zalo. Login is phone number + password.
- Time zone Asia/Ho_Chi_Minh.

## Capabilities and Constraints

- Shipped: rooms, manual bookings (hold/confirmed/cancelled), per-place timeline calendar with OTA conflicts, hourly iCal sync + sync log, check-in/out, early check-in, room move, housekeeping clean/dirty, lưu trú badge, activity log, owner monthly report, user/membership management, public vacancy API.
- Roles: owner (`:manage`) vs staff (`:operate`) per homestay; admins run accounts only.
- **Roadmap:** `hueni_mini_pms_detailed_design.md` (local draft) — grow into a mini PMS: guests, payments/balances, booking services, unit types, housekeeping/maintenance tasks. Already-shipped iCal sync stays even though that draft lists OTA sync as a non-goal. GitHub issues remain the authority where they differ.
- Stack fixed: Rails 8, server-rendered ERB + Turbo/Stimulus (importmap), Tailwind 4 + daisyUI 5, SQLite. No Node build.
- Place details (address, phone, rating, photos…) are a read-only copy from hueni; never edited here.
- Public API never exposes guest data, feed URLs or OTA uids.

## Brand Commitments

- All UI copy in Vietnamese, plain and short; established terms: Hôm nay, Phòng trống, Nhận phòng / Trả phòng, Nhận phòng sớm, Dọn xong, Đã khai báo lưu trú, Hoàn tác, OTA đã huỷ, Lịch sử, Đồng bộ ngay, Sắp có.
- The admin does not follow hueni.me's design; it uses daisyUI's `autumn` theme only (binding until a deliberate redesign).
- Mobile-first: bottom dock on phones, sidebar on `lg+`.

## Evidence on Hand

- Demo data: `db/seeds/development.rb` (made-up). Real homestay data lives in the private hue-ni repo and must never be committed here.
- No testimonials, owner counts, booking volumes or traffic numbers exist — do not fabricate them.

## Product Principles

1. Vacancy truth first — every feature serves an accurate "room free/occupied" answer; `Booking.occupying` is its single definition.
2. One-thumb operations — daily front-desk actions must be fast and obvious on a phone for non-technical users.
3. Record facts, don't block reality — check-in/out record what happened; OTA bookings are shown as conflicts, not rejected.
4. Never lose history — cancelled and OTA-removed bookings stay visible; changes are logged.
5. Privacy by default — guest data and feed tokens never leave the admin.

## Accessibility & Inclusion

Older, low-tech-comfort users on phones: large tap targets, readable text sizes, clear Vietnamese labels over icons alone, no hover-only actions.
