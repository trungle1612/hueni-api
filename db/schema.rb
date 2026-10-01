# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_01_143716) do
  create_table "bookings", force: :cascade do |t|
    t.integer "room_id", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.string "status", default: "confirmed", null: false
    t.string "source", default: "manual", null: false
    t.string "guest_name"
    t.string "guest_phone"
    t.text "note"
    t.integer "calendar_feed_id"
    t.string "uid"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["calendar_feed_id", "uid"], name: "index_bookings_on_calendar_feed_id_and_uid", unique: true
    t.index ["room_id", "start_date", "end_date"], name: "index_bookings_on_room_id_and_start_date_and_end_date"
    t.check_constraint "end_date > start_date", name: "bookings_dates_order"
    t.check_constraint "source IN ('manual', 'ical')", name: "bookings_source_values"
    t.check_constraint "status IN ('hold', 'confirmed', 'cancelled')", name: "bookings_status_values"
  end

  create_table "calendar_feeds", force: :cascade do |t|
    t.integer "room_id", null: false
    t.string "url", null: false
    t.string "provider", default: "other", null: false
    t.datetime "last_synced_at"
    t.text "last_error"
    t.datetime "last_error_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id", "url"], name: "index_calendar_feeds_on_room_id_and_url", unique: true
    t.check_constraint "provider IN ('airbnb', 'booking', 'other')", name: "calendar_feeds_provider_values"
  end

  create_table "places", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.string "address"
    t.string "phone"
    t.decimal "rating", precision: 2, scale: 1
    t.decimal "lat", precision: 10, scale: 7
    t.decimal "lng", precision: 10, scale: 7
    t.string "website"
    t.string "cover_image_url"
    t.string "google_place_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_places_on_slug", unique: true
  end

  create_table "rooms", force: :cascade do |t|
    t.integer "place_id", null: false
    t.string "name", null: false
    t.integer "max_guests", null: false
    t.integer "price"
    t.json "photo_urls", default: [], null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["place_id", "name"], name: "index_rooms_on_place_id_and_name", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.string "role", default: "owner", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.check_constraint "role IN ('admin', 'owner')", name: "users_role_values"
  end

  add_foreign_key "bookings", "calendar_feeds"
  add_foreign_key "bookings", "rooms"
  add_foreign_key "calendar_feeds", "rooms"
  add_foreign_key "rooms", "places"
  add_foreign_key "sessions", "users"
end
