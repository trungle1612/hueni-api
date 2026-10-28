# Booking detail: the booking plus its money. Staff see the totals and what is due, not the nightly quote.
class MiniApp::BookingDetailSerializer < MiniApp::BookingSerializer
  attributes :room_total, :total, :paid, :due
  many(:payments, resource: MiniApp::PaymentSerializer) { |payments| payments.sort_by(&:created_at) }
  many(:charges, resource: MiniApp::ChargeSerializer) { |charges| charges.sort_by(&:created_at) }
end
