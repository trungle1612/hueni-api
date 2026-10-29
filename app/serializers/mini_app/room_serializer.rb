# The Mini App's Room. params[:manage]: owners only get the prices and the room note (staff never, like /admin).
class MiniApp::RoomSerializer
  include Alba::Resource

  attributes :id, :place_id, :name, :max_guests, :active, :housekeeping, :floor, :damage_note
  # Labels to show (kind, amenities) and the keys a room form sends back (room_type, amenity_keys).
  attributes :room_type
  attribute(:kind) { Room::ROOM_TYPES[it.room_type] }
  attribute(:amenity_keys) { it.amenities }
  attribute(:amenities) { it.amenities.map { Room::AMENITIES[it] } }
  # until = the last blocked day, inclusive (Room#maintenance_on?).
  attribute(:maintenance, if: proc { |room| room.maintenance? }) { { reason: it.maintenance_reason, until: it.maintenance_until } }
  attributes :price, :weekend_price, :note, if: proc { params[:manage] }
end
