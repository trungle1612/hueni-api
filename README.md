## Rails 8 backend for hueni.me — the Huế travel guide.

- Vacancy API — GET /v1/vacancy returns free homestay rooms today, used by hueni's "Phòng trống" tab.
- Owner admin — homestay owners manage rooms, calendar feeds, and manual bookings at /admin.
- iCal sync — hourly import of bookings from Airbnb / Booking.com calendars.

## Stack

- Rails 8 · Ruby 3.4 · SQLite · Solid Queue/Cache/Cable · Hotwire · Kamal 2 · Litestream

## Backups

`config/litestream.yml` + the Kamal accessory `litestream` stream `production.sqlite3` to the Cloudflare R2 bucket `hueni-api-backup` (prefix `production/`): changes uploaded every 10 s, a snapshot daily, any point in the last 7 days restorable. The queue / cache / cable databases are not backed up (rebuilt empty on boot).

Locally, load the secrets first (`set -a; source .env; set +a`; `.env` is git-ignored and holds `DEPLOY_HOST`, `RAILS_MASTER_KEY`, `LITESTREAM_*`).

```bash
bin/kamal accessory boot litestream      # first time (kamal deploy does not start accessories)
bin/kamal accessory reboot litestream    # after changing config/litestream.yml or its secrets
bin/kamal accessory logs litestream
```

### Restore

On the VPS, restore into a scratch file first and check it:

```bash
# -u 1000:1000: the file belongs to the app's user (and to `deploy`, same uid)
docker exec -u 1000:1000 hueni_api-litestream litestream restore -config /etc/litestream.yml \
  -o /data/restore.sqlite3 /data/production.sqlite3
# point in time: add  -timestamp 2026-10-11T14:00:00Z
# the VPS has no sqlite3; the app image does
docker exec $(docker ps -q --filter label=service=hueni_api --filter label=role=web) \
  sqlite3 storage/restore.sqlite3 "select count(*) from users; select count(*) from bookings;"
```

To replace the live database:

```bash
bin/kamal app stop && bin/kamal accessory stop litestream
cd /var/lib/hueni-api/storage
mkdir -p broken && mv production.sqlite3* broken/          # keep the old files
mv restore.sqlite3 production.sqlite3
bin/kamal accessory boot litestream && bin/kamal app boot
```

If the VPS is gone: deploy to a new one, then run the same `litestream restore` there (the accessory only needs the R2 secrets) before `bin/kamal app boot`.
