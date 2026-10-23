# Giữ chỗ is gone (#127): every booking is confirmed or cancelled; Đã cọc shows whether money came in.
class RemoveHoldStatus < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE bookings SET status = 'confirmed' WHERE status = 'hold'"
    remove_check_constraint :bookings, name: "bookings_status_values"
    add_check_constraint :bookings, "status IN ('confirmed', 'cancelled')", name: "bookings_status_values"
  end

  def down
    remove_check_constraint :bookings, name: "bookings_status_values"
    add_check_constraint :bookings, "status IN ('hold', 'confirmed', 'cancelled')", name: "bookings_status_values"
  end
end
