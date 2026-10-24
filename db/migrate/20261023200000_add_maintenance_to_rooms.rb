# Bảo trì (#121): a room state beside clean / dirty, with a reason and the last day it is blocked.
class AddMaintenanceToRooms < ActiveRecord::Migration[8.1]
  def change
    add_column :rooms, :maintenance_reason, :string
    add_column :rooms, :maintenance_until, :date
    remove_check_constraint :rooms, "housekeeping IN ('clean', 'dirty')", name: "rooms_housekeeping_values"
    add_check_constraint :rooms, "housekeeping IN ('clean', 'dirty', 'maintenance')", name: "rooms_housekeeping_values"
  end
end
