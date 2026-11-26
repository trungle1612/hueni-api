# Hiển thị trên hue-ni (#302): rooms are switched on or off one by one, whatever their type. The hidden types become
# hidden rooms; site_hidden_room_types stays for the frozen Mini App to read. A request may now name no room type.
class AddSiteHiddenRoomIds < ActiveRecord::Migration[8.1]
  def up
    add_column :places, :site_hidden_room_ids, :json, null: false, default: []
    change_column_null :booking_requests, :room_type, true
    execute <<~SQL
      UPDATE places SET site_hidden_room_ids = COALESCE((
        SELECT json_group_array(rooms.id) FROM rooms
        WHERE rooms.place_id = places.id AND rooms.room_type IN (SELECT value FROM json_each(places.site_hidden_room_types))
      ), '[]')
    SQL
  end

  def down
    remove_column :places, :site_hidden_room_ids
    change_column_null :booking_requests, :room_type, false, "double"
  end
end
