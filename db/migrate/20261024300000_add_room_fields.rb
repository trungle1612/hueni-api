# Room fields (#138): Tầng, Loại phòng (fixed list, Room::ROOM_TYPES), tiện nghi, ghi chú nội bộ.
class AddRoomFields < ActiveRecord::Migration[8.1]
  def change
    add_column :rooms, :room_type, :string
    add_check_constraint :rooms, "room_type IN ('single', 'double', 'family', 'dorm', 'studio', 'villa')", name: "rooms_room_type_values"
    add_column :rooms, :floor, :integer
    add_column :rooms, :amenities, :json, null: false, default: []
    add_column :rooms, :note, :text
  end
end
