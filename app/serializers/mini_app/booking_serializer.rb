# The Mini App's Booking. Preload :calendar_feed and :payments (awaiting_deposit reads the payments).
# params[:manage]: owners only get the nightly quote.
class MiniApp::BookingSerializer
  include Alba::Resource

  attributes :id, :code, :label, :room_id, :start_date, :end_date, :status, :source,
    :guest_name, :guest_phone, :guests, :note, :cancel_reason,
    :checked_in_at, :checked_out_at, :declared_at, :removed_from_feed_at
  attribute(:provider) { it.calendar_feed&.provider }
  attribute(:discount, if: proc { |booking| booking.discount }) { { amount: it.discount, reason: it.discount_reason } }
  attribute(:awaiting_deposit) { it.awaiting_deposit? }
  attributes :price, :weekend_price, if: proc { params[:manage] }
end
