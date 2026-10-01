class CreateCalendarFeeds < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_feeds do |t|
      t.references :room, null: false, foreign_key: true, index: false
      t.string :url, null: false # secret: OTA feed URLs embed access tokens
      t.string :provider, null: false, default: "other"
      t.datetime :last_synced_at
      t.text :last_error
      t.datetime :last_error_at
      t.timestamps

      t.check_constraint "provider IN ('airbnb', 'booking', 'other')", name: "calendar_feeds_provider_values"
    end
    add_index :calendar_feeds, [ :room_id, :url ], unique: true
    add_foreign_key :bookings, :calendar_feeds
  end
end
