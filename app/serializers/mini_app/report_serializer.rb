# One homestay's period in numbers (Report), owners only. Ratios are 0..1 (nil when nothing to divide);
# previous = the same numbers for the period before (a month in progress: the same days), absent for a future month.
class MiniApp::ReportSerializer
  include Alba::Resource

  attribute(:period) { it.month? ? it.month.strftime("%Y-%m") : "7d" }
  attributes :first, :finish, :last, :days
  attribute(:current) { it.current? }
  attribute(:future) { it.future? }
  attribute(:empty) { it.empty? }

  attributes :revenue, :sold, :available, :occupancy, :booking_count, :outcomes, :ota_cancelled, :cancellation_rate, :alos, :ahead, :ahead_revenue, :due
  attribute(:adr) { it.adr&.round }
  attribute(:unpriced) { it.unpriced? }

  attribute(:channels) { it.channels.map { |key, numbers| { key:, label: Report::CHANNEL_LABELS[key], **numbers } } }
  attribute(:rooms) { it.rooms.map { room_row(it) } }
  attribute(:top_rooms) { it.top_rooms.map { room_row(it) } }
  # Công nợ chưa thu: Booking + due + overdue (the guest has left, or should have).
  attribute(:debts) do |report|
    report.debts.map { MiniApp::BookingSerializer.new(it, params:).serializable_hash.merge(due: it.due, overdue: report.overdue?(it)) }
  end
  attribute(:previous, if: proc { |report| !report.future? }) do
    it.previous.then { { first: it.first, last: it.last, revenue: it.revenue, occupancy: it.occupancy, adr: it.adr&.round, alos: it.alos, cancellation_rate: it.cancellation_rate } }
  end

  def room_row(row) = { room_id: row.room.id, name: row.room.name, sold: row.sold, revenue: row.revenue }
end
