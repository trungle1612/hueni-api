# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Rails 8 backend for **hueni** (`https://hueni.me`, private repo `trungle1612/hue-ni`, usually checked out at `../hue-ni`), a static React travel guide for Huế. It provides:

1. `GET /v1/vacancy` — public JSON of free homestay rooms today, consumed by hueni's "Phòng trống" tab.
2. `/admin` — owner admin (Hotwire, not built yet): owners manage rooms, calendar feeds and bookings.
3. iCal sync pulling bookings from owners' Airbnb / Booking.com calendars: `CalendarFeed#sync` + `SyncCalendarFeedJob` (hourly schedule is #15).

**Design spec:** `../hue-ni/docs/superpowers/specs/2026-09-26-hueni-api-design.md` (lives in the hue-ni repo). Work is tracked as GitHub issues grouped under epics #12 (Step 1), #16 (Step 2), #24 (Step 3), #28 (Step 4). **Issue bodies are newer than the spec** where they differ — see "Deviations" below. If code, issue and spec disagree, ask.

## Commands

rbenv shims are not on PATH in non-interactive shells; prefix commands with `export PATH=~/.rbenv/shims:$PATH &&` (system Ruby is 2.6).

```bash
bin/setup                                  # gems + DB
bin/dev                                    # http://localhost:3000
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

**Data model** (`db/schema.rb`): `places` → `rooms` → `bookings`, plus `calendar_feeds` (room → feed → its imported bookings).

- `places.slug` = hueni's `Place.id`. Other place columns (address, phone, rating, lat/lng, …) are a **read-only copy** of hueni's `homestay.json`, overwritten by `places:import`. hueni stays the source of truth; never edit them here.
- `bookings`: `end_date` is **exclusive** (checkout day is free). `status` = `hold` | `confirmed` | `cancelled`; `source` = `manual` | `ical`. Values are enforced by DB check constraints *and* `enum ..., validate: true`. Cancelled rows are kept as history, not deleted.
- `Booking.blocking_on(date)` (hold + confirmed covering `date`) is the single definition of "room occupied" — vacancy and the admin timeline both build on it.

**Vacancy** (`app/models/vacancy.rb`): `Vacancy.on(date)` computes `{ slug => { left:, max_guests: } }`; `Vacancy.cached` wraps it in `Rails.cache` under `["vacancy", Date.current]` for 5 min. Every `Place`, `Room`, `Booking` and `CalendarFeed` has `after_commit { Vacancy.bust }`. **Bulk writes that skip callbacks (`delete_all`, `upsert_all`, the iCal sync) must call `Vacancy.bust` themselves.**

**Public API** (`app/controllers/v1/`): controllers inherit `ActionController::API`, not `ApplicationController` (which has `allow_browser :modern` and would block curl/uptime checks). CORS is a hand-set `Access-Control-Allow-Origin` for `https://hueni.me` and `http://localhost:5173` only — no `rack-cors`. `/v1/*` must never expose guest fields, feed URLs or `uid`s; the request test asserts this.

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
- Planned admin rule: every `/admin` controller inherits `Admin::BaseController` and scopes through `Current.user.accessible_place_ids`; out-of-scope → 404.

## Conventions

- All user-facing strings in Vietnamese. Admin UI: server-rendered ERB + Turbo/Stimulus via importmap, plain CSS with hueni's "Imperial Huế" tokens (primary `#7d0010`, gold `#735c00`, background `#fdf6ec`, text `#2b1613`; Noto Serif headings, Plus Jakarta Sans body), mobile-first.
- SQLite for everything (primary + Solid Queue/Cache/Cable). No Redis, no Postgres, no Node build.
- Prefer stdlib over new gems (e.g. `Resolv`/`IPAddr` for SSRF, `Net::HTTP`).
- HTTP in tests is blocked by WebMock (`webmock/minitest`, localhost allowed); stub every external request. Use public IP literals (e.g. `https://1.1.1.1/…`) for feed URLs so validation needs no DNS.
- Minitest 6: `stub`/`minitest-mock` are not available — swap collaborators directly (e.g. `Rails.cache = ActiveSupport::Cache::MemoryStore.new` with `ensure` restore; test env cache is `:null_store`).
- Unmerged migrations may be edited in place; once on `main`, add a new migration.
- One branch + PR per issue (`<issue>-<slug>`), PR body `Closes #N`. Never push to `main`.

## Deployment (planned, issues #8–#10)

Kamal 2 → the project VPS (host/user in the spec, not in this public repo); image built in GitHub Actions and pushed to GHCR. kamal-proxy on `127.0.0.1:8080` without TLS; the existing nginx serves `api.hueni.me` → `:8080` with certbot. **Kamal must not take ports 80/443** — nginx serves hueni.me there. SQLite on host volume `/var/lib/hueni-api/storage` → `/rails/storage`, backed up by a Litestream accessory to Cloudflare R2. `config/deploy.yml` is still the generated default.
