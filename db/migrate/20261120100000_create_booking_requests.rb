# Hiển thị trên hue-ni (#282): approve mode (a guest's request the homestay answers before a booking exists), the reply
# deadline, showing the phone after accept, and the check-in / check-out times and house rules guests see.
class CreateBookingRequests < ActiveRecord::Migration[8.1]
  def change
    change_table :places, bulk: true do |t|
      t.string :site_mode, null: false, default: "approve"
      t.integer :site_reply_minutes, null: false, default: 30
      t.boolean :site_show_phone, null: false, default: false
      t.string :check_in_time
      t.string :check_out_time
      t.text :house_rules
      t.check_constraint "site_mode IN ('approve', 'auto')", name: "places_site_mode"
    end
    # A page already open keeps today's behaviour.
    up_only { execute "UPDATE places SET site_mode = 'auto' WHERE site_open" }

    create_table :booking_requests do |t|
      t.references :place, null: false, foreign_key: true
      t.references :booking, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.datetime :reply_by, null: false
      t.string :room_type, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.integer :guests, null: false
      t.string :guest_name, null: false
      t.string :guest_phone, null: false
      t.text :note
      t.integer :deposit_percent
      t.string :decline_reason
      t.date :suggested_start_date
      t.date :suggested_end_date
      t.timestamps
      t.check_constraint "status IN ('pending', 'accepted', 'declined', 'expired')", name: "booking_requests_status"
      t.check_constraint "decline_reason IS NULL OR decline_reason IN ('full', 'dates', 'rules')", name: "booking_requests_decline_reason"
    end
    add_index :booking_requests, %i[status reply_by]
  end
end
