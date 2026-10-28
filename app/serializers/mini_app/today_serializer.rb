# Hôm nay / Ngày mai and Cần xử lý (Today).
class MiniApp::TodaySerializer
  include Alba::Resource

  attributes :date
  many :arrivals, resource: MiniApp::BookingSerializer
  many :departures, resource: MiniApp::BookingSerializer
  many :in_house, resource: MiniApp::BookingSerializer
  many :dirty_rooms, resource: MiniApp::RoomSerializer
  # error = OTA conflict (date: the calendar day to open), clean = arrival to a dirty room, stay = no lưu trú yet.
  many :issues do
    attributes :kind, :title, :detail, :date
    attribute(:booking_id) { it.booking.id }
  end
end
