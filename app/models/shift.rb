# Giao ca (#167): the till of one homestay since its last close. Cash only: transfers and cards are listed
# apart and never in the till.
class Shift
  attr_reader :place, :last_close

  def initialize(place)
    @place = place
    @last_close = place.shift_closes.order(:created_at, :id).last
  end

  def since = last_close&.created_at
  def opening = last_close&.keep || 0
  def expenses = after_close(place.cash_expenses).includes(:user).order(:created_at).to_a
  def expenses_total = expenses.sum(&:amount)
  def cash_in = payments("cash").select(&:payment?).sum(&:amount)
  def cash_out = payments("cash").select(&:refund?).sum(&:amount)
  def expected = opening + cash_in - cash_out - expenses_total
  # Chuyển khoản / thẻ since the last close (payments minus refunds), not in the till.
  def other = %w[bank card].index_with { |method| payments(method).sum(&:signed_amount) }

  # Chốt ca: the server's expected, the count (a total, or { "500000" => 2, … } added up) and what stays in the till.
  def close(user:, counted: nil, denominations: nil, keep: nil, handed_to_id: nil, note: nil)
    denominations = denominations.to_h.transform_keys(&:to_s).transform_values(&:to_i).select { |value, count| value.to_i.in?(ShiftClose::DENOMINATIONS) && count.positive? }.presence
    counted = denominations.sum { |value, count| value.to_i * count } if denominations
    place.shift_closes.create(user:, opening:, expected:, counted:, denominations:, keep:, handed_to_id:, note:)
  end

  private
    def after_close(scope) = since ? scope.where("#{scope.table_name}.created_at > ?", since) : scope

    def payments(method)
      @payments ||= after_close(Payment.joins(booking: :room).where(rooms: { place_id: place.id })).to_a
      @payments.select { it.payment_method == method }
    end
end
