# The profile: stats (Lần ở · Đã trả · Còn nợ), Ghi chú cho lễ tân and every booking, newest first.
class MiniApp::GuestProfileSerializer < MiniApp::GuestSerializer
  attributes :note, :paid, :due
  many :bookings, resource: MiniApp::BookingSerializer
end
