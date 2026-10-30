# Trang đặt phòng riêng (#172): the homestay's own booking page settings, and online bookings held until the deposit comes in.
class AddBookingSite < ActiveRecord::Migration[8.1]
  def change
    change_table :places, bulk: true do |t|
      t.boolean :site_open, null: false, default: false
      t.integer :site_deposit_percent, null: false, default: 30
      t.json :site_hidden_room_types, null: false, default: []
      t.integer :site_hold_minutes, null: false, default: 30
      t.integer :site_cutoff_hour, null: false, default: 20
    end

    change_table :bookings, bulk: true do |t|
      t.boolean :online, null: false, default: false
      t.datetime :hold_expires_at
    end
    add_index :bookings, :hold_expires_at
  end
end
