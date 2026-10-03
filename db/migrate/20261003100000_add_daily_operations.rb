class AddDailyOperations < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :checked_in_at, :datetime
    add_column :bookings, :checked_out_at, :datetime
    add_column :bookings, :guests, :integer
    add_check_constraint :bookings, "checked_out_at IS NULL OR checked_in_at IS NOT NULL", name: "bookings_checkout_after_checkin"

    add_column :rooms, :housekeeping, :string, null: false, default: "clean"
    add_check_constraint :rooms, "housekeeping IN ('clean', 'dirty')", name: "rooms_housekeeping_values"
  end
end
