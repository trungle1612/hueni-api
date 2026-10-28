# The Mini App's RoomDay: a room's state today, the booking in it and the next one.
class MiniApp::RoomDaySerializer
  include Alba::Resource

  one :room, resource: MiniApp::RoomSerializer
  attributes :state
  one :booking, resource: MiniApp::BookingSerializer
  one :next_booking, key: :next, resource: MiniApp::BookingSerializer
end
