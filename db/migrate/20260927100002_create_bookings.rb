class CreateBookings < ActiveRecord::Migration[8.1]
  def change
    create_table :bookings do |t|
      t.references :room, null: false, foreign_key: true, index: false
      t.date :start_date, null: false
      t.date :end_date, null: false # exclusive (checkout day)
      t.string :status, null: false, default: "confirmed"
      t.string :source, null: false, default: "manual"
      t.string :guest_name
      t.string :guest_phone
      t.text :note
      t.integer :calendar_feed_id # FK added with calendar_feeds (#13)
      t.string :uid
      t.timestamps

      t.check_constraint "end_date > start_date", name: "bookings_dates_order"
      t.check_constraint "status IN ('hold', 'confirmed', 'cancelled')", name: "bookings_status_values"
      t.check_constraint "source IN ('manual', 'ical')", name: "bookings_source_values"
    end
    add_index :bookings, [ :room_id, :start_date, :end_date ]
    add_index :bookings, [ :calendar_feed_id, :uid ], unique: true
  end
end
