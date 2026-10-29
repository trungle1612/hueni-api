# Đặt phòng theo đoàn (#164): the group, its rooms (cancelled = Bỏ khỏi đoàn, left out) and the bill.
# total / paid / due sum the billed rooms: all of them on split bills, minus Khách tự trả (pays_own) on one bill.
class MiniApp::GroupSerializer
  include Alba::Resource

  attributes :id, :code, :name, :contact, :phone, :origin, :discount_pct, :bill
  many :bookings, source: proc { rooms_booked }, resource: MiniApp::BookingDetailSerializer
  attribute(:total) { |group| group.billed.sum { it.total || 0 } }
  attribute(:paid) { |group| group.billed.sum(&:paid) }
  attribute(:due) { |group| group.billed.sum { it.due || 0 } }
end
