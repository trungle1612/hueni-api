# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Rails 8 backend for **hueni** (`https://hueni.me`, private repo `trungle1612/hue-ni`, usually checked out at `../hue-ni`), a static React travel guide for Huế. It provides:

1. `GET /v1/vacancy` — public JSON of free homestay rooms today, consumed by hueni's "Phòng trống" tab.
2. `/admin` — owner admin (Hotwire): owners manage rooms, calendar feeds and bookings; admins also manage users.
3. iCal sync pulling bookings from owners' Airbnb / Booking.com calendars: `CalendarFeed#sync` + `SyncCalendarFeedJob` (hourly schedule is #15).

**Design spec:** `../hue-ni/docs/superpowers/specs/2026-09-26-hueni-api-design.md` (lives in the hue-ni repo). Work is tracked as GitHub issues grouped under epics #12 (Step 1), #16 (Step 2), #24 (Step 3), #28 (Step 4). **Issue bodies are newer than the spec** where they differ — see "Deviations" below. If code, issue and spec disagree, ask.

## Commands

rbenv shims are not on PATH in non-interactive shells; prefix commands with `export PATH=~/.rbenv/shims:$PATH &&` (system Ruby is 2.6).

```bash
bin/setup                                  # gems + DB
bin/dev                                    # http://localhost:3000 (server + Tailwind watcher)
bin/rails test                             # all non-system tests
bin/rails test test/models/vacancy_test.rb      # one file
bin/rails test test/models/vacancy_test.rb:12   # one test by line
bin/rails test:system
bin/rubocop                                # rubocop-rails-omakase
bin/brakeman --no-pager                    # runs with --ensure-latest: fails if a newer brakeman exists → bundle update brakeman --conservative
bin/rails places:import[path]              # upsert places from hueni's homestay.json (default db/places/homestay.json)
```

CI (`.github/workflows/ci.yml`) runs brakeman, bundler-audit, importmap audit, rubocop, `bin/rails db:test:prepare test` and `test:system` on every PR.

## Architecture

**Data model** (`db/schema.rb`): `places` → `rooms` → `bookings`, plus `calendar_feeds` (room → feed → its imported bookings) and `place_memberships` (users ↔ places, many-to-many).

- `places.slug` = hueni's `Place.id`. Other place columns (address, phone, rating, lat/lng, …) are a **read-only copy** of hueni's `homestay.json`, overwritten by `places:import`. hueni stays the source of truth; never edit them here.
- `bookings`: `end_date` is **exclusive** (checkout day is free). `status` = `hold` | `confirmed` | `cancelled`; `source` = `manual` | `ical`. Values are enforced by DB check constraints *and* `enum ..., validate: true`. Cancelled rows are kept as history, not deleted.
- `Booking.blocking_on(date)` (hold + confirmed covering `date`) is the single definition of "room occupied" — vacancy and the admin timeline both build on it.
- A manual hold/confirmed booking can't overlap another blocking booking on its room (validation). iCal bookings skip it (the OTA already sold the nights); an iCal booking overlapping a manual one is shown on the calendar as a conflict for the owner to resolve.
- Check-in/out are timestamps (`bookings.checked_in_at` / `checked_out_at`) beside `status`, not statuses: the iCal sync rewrites `status` on every run. `Booking#check_in` / `#check_out` return true/false (reason in `errors[:base]`); check-out marks the room `dirty`. `rooms.housekeeping` (`clean` | `dirty`) is independent of vacancy. `RoomDay.for(rooms)` is the single "room state today" (off / leaving / occupied / arriving / held / free) for the dashboard board and the homestay page; `Admin::StaysHelper` renders its badges and the Check-in / Check-out / Dọn xong buttons. Staff can do all of it; no-show = cancel the booking with a note.

**Vacancy** (`app/models/vacancy.rb`): `Vacancy.on(date)` computes `{ slug => { left:, max_guests: } }`; `Vacancy.cached` wraps it in `Rails.cache` under `["vacancy", Date.current]` for 5 min. Every `Place`, `Room`, `Booking` and `CalendarFeed` has `after_commit { Vacancy.bust }`. **Bulk writes that skip callbacks (`delete_all`, `upsert_all`, the iCal sync) must call `Vacancy.bust` themselves.**

**Public API** (`app/controllers/v1/`): controllers inherit `ActionController::API`, not `ApplicationController` (which has `allow_browser :modern` and would block curl/uptime checks). CORS is a hand-set `Access-Control-Allow-Origin` for `https://hueni.me` and `http://localhost:5173` only — no `rack-cors`. `/v1/*` must never expose guest fields, feed URLs or `uid`s; the request test asserts this.

**Auth & admin:** Rails 8 authentication generator (`Authentication` concern in `ApplicationController`, DB-backed `sessions`) — every controller requires login unless it calls `allow_unauthenticated_access`. `users.role` = `admin` | `user`; rights per homestay come from `place_memberships.role` = `owner` | `staff` (a homestay keeps at least one owner — model rule). The one authorization rule is `User#allowed_to?(:manage, place)` (admins: always); controllers call `authorize!(:manage, place)` after the scoped lookup, views use the `allowed_to?` helper. Owner-only: rooms new/create/edit/update, feeds create/destroy, members (`Admin::MembersController`). Staff: dashboard, homestay page (no prices), calendar, bookings, feed sync. Admin controllers inherit `Admin::BaseController` (scoping in #18). The admin menu is one list, `ApplicationHelper#admin_menu_items`, rendered as a bottom dock on phones and a sidebar on `lg+`; `path: nil` items show as "Sắp có".

**Login is phone number + password** (Zalo login planned; no email or mailer). `users.phone_number` is normalized to 10 digits starting with 0 (`+84 912 345 678` → `0912345678`); `normalizes` also rewrites values in `where(phone_number: …)`, so use raw SQL to match non-phone strings. Admins create users at `/admin/users` and get a one-time link (`/dat-mat-khau/:token`, `generates_token_for :password_setup`, 7 days, invalidated by any password change) to send over Zalo; the user picks their own password there and is logged in. "Tạo link đặt lại mật khẩu" also locks the old password and ends every session. The link is shown once via `flash[:setup_link]` (the layout renders only `notice` / `alert`). `bin/rails db:seed` loads made-up demo data in development (`db/seeds/development.rb`).

**Time:** `config.time_zone = "Asia/Ho_Chi_Minh"`. Always `Date.current` / `Time.current`. A Huế day starts at 17:00 UTC; tests use `travel_to`.

## Deviations from the spec (agreed, already in issues)

- `places` table with FKs instead of string `place_id` + `config/places.yml`.
- Bookings have `status` (hold/confirmed/cancelled) and optional `guest_name`, `guest_phone`, `note`; holds block vacancy and never expire.
- Rooms have `price` (VND/night, admin-only) and `photo_urls` (JSON array of http(s) URLs).
- Admin calendar (#21) is a per-place timeline (rooms × days); iCal bookings overlapping manual ones are shown as conflicts.

## Security invariants

- **This repo is public; hue-ni is private.** Never commit data copied from hue-ni (`db/places/*.json` is git-ignored). Test fixtures use made-up data.
- `calendar_feeds.url` embeds OTA tokens: never render it in `/v1/*`, keep `:url` in `filter_parameters`.
- SSRF: feed URLs must be http(s) and resolve only to public IPs (`CalendarFeed.public_ip?`), checked on save **and again at fetch time** (DNS rebinding).
- iCal sync failure must change no bookings; record `last_error` / `last_error_at` instead. `CalendarFeed#sync` fetches and parses *before* opening the transaction.
- Admin rule: every admin lookup goes through `Current.user.accessible_places / _rooms / _calendar_feeds / _bookings` (admins: everything; owners: places they are members of). Never `Place.find` / `Room.find` etc. in admin controllers. Use `find` / `find_by!` (never `find_by`, which returns nil → 500). Never permit `place_id` / `room_id` / `calendar_feed_id` in params; build children through a scoped parent (`Current.user.accessible_rooms.find(params[:room_id]).bookings.build(...)`). Out of scope → `RecordNotFound` → 404. In scope but not allowed (staff on an owner-only action) → `Admin::BaseController::Forbidden` → 403 page. Each new admin page adds a request test that another owner's record returns 404; each owner-only action also tests staff → 403.

## Conventions

- All user-facing strings in Vietnamese, inline in views/controllers. Admin UI: server-rendered ERB + Turbo/Stimulus via importmap, **Tailwind 4 + daisyUI 5 (`autumn` theme only)** via `tailwindcss-rails`; daisyUI is the vendored `app/assets/tailwind/daisyui.mjs` (update by re-downloading; keep `@source not "./daisyui.mjs"` or every daisyUI class gets emitted). Mobile-first. The admin does not follow hueni's design.
- SQLite for everything (primary + Solid Queue/Cache/Cable). No Redis, no Postgres, no Node build.
- Prefer stdlib over new gems (e.g. `Resolv`/`IPAddr` for SSRF, `Net::HTTP`).
- HTTP in tests is blocked by WebMock (`webmock/minitest`, localhost allowed); stub every external request. Use public IP literals (e.g. `https://1.1.1.1/…`) for feed URLs so validation needs no DNS.
- Minitest 6: `stub`/`minitest-mock` are not available — swap collaborators directly (e.g. `Rails.cache = ActiveSupport::Cache::MemoryStore.new` with `ensure` restore; test env cache is `:null_store`).
- Unmerged migrations may be edited in place; once on `main`, add a new migration.
- One branch + PR per issue (`<issue>-<slug>`), PR body `Closes #N`. Never push to `main`.

## Deployment (planned, issues #8–#10)

Kamal 2 → the project VPS (host/user in the spec, not in this public repo); image built in GitHub Actions and pushed to GHCR. kamal-proxy on `127.0.0.1:8080` without TLS; the existing nginx serves `api.hueni.me` → `:8080` with certbot. **Kamal must not take ports 80/443** — nginx serves hueni.me there. SQLite on host volume `/var/lib/hueni-api/storage` → `/rails/storage`, backed up by a Litestream accessory to Cloudflare R2. `config/deploy.yml` is still the generated default.
