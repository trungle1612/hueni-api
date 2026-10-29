# Booking detail: the booking plus its money. Staff see the totals and what is due, not the nightly quote.
class MiniApp::BookingDetailSerializer < MiniApp::BookingSerializer
  attributes :room_total, :total, :paid, :due
  # Cần lưu ý from Hồ sơ khách (#165), so the desk sees it on every booking of a flagged guest.
  attribute(:guest_flag) { Guest.where(place_id: it.room.place_id, key: Guest.key_for(it)).pick(:flag) }
  many(:payments, resource: MiniApp::PaymentSerializer) { |payments| payments.sort_by(&:created_at) }
  many(:charges, resource: MiniApp::ChargeSerializer) { |charges| charges.sort_by(&:created_at) }
end
