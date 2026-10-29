# Giao ca (#167): owners and staff. The till of a homestay since its last close, its cash expenses, and Chốt ca.
# A cash expense can be changed or deleted by whoever wrote it, or an owner, until the shift is closed.
class MiniApp::V1::ShiftsController < MiniApp::V1::BaseController
  before_action :set_place, only: %i[show close create_expense]
  before_action :set_expense, only: %i[update_expense destroy_expense]
  before_action -> { authorize!(:operate, @place) }

  def show = render_shift

  # { shift_close: { counted | denominations: { "500000": 2, … }, keep, handed_to_id, note } }
  def close
    attrs = params.expect(shift_close: [ :counted, :keep, :handed_to_id, :note, denominations: ShiftClose::DENOMINATIONS.map(&:to_s) ])
    record = Shift.new(@place).close(user: Current.user, **attrs.to_h.symbolize_keys)
    record.persisted? ? render(json: { close: close_json(record), shift: shift_json }, status: :created) : render_invalid(record)
  end

  def create_expense
    expense = @place.cash_expenses.build(expense_params.merge(user: Current.user))
    expense.save ? render_shift(status: :created) : render_invalid(expense)
  end

  def update_expense = @expense.update(expense_params) ? render_shift : render_invalid(@expense)

  def destroy_expense
    @expense.destroy!
    render_shift
  end

  private
    def set_place
      @place = Current.user.accessible_places.find(params[:id])
    end

    def set_expense
      @expense = CashExpense.where(place: Current.user.accessible_places).find(params[:id])
      @place = @expense.place
      raise Forbidden unless @expense.user_id == Current.user.id || manage?
      return unless @expense.closed?
      @expense.errors.add(:base, "Ca đã chốt, không sửa được khoản chi này.")
      render_invalid(@expense)
    end

    def expense_params = params.expect(expense: %i[amount reason])

    def render_shift(status: :ok) = render(json: shift_json, status:)

    def shift_json
      shift = Shift.new(@place)
      {
        since: shift.since, opening: shift.opening, cash_in: shift.cash_in, cash_out: shift.cash_out,
        expenses_total: shift.expenses_total, expected: shift.expected, other: shift.other,
        expenses: shift.expenses.map { { id: it.id, amount: it.amount, reason: it.reason, at: it.created_at, by: it.user&.name, user_id: it.user_id } },
        last_close: shift.last_close&.then { close_json(it) }
      }
    end

    def close_json(record)
      record.slice(:id, :opening, :expected, :counted, :denominations, :keep, :note, :difference).merge(
        at: record.created_at, by: record.user&.name, handed_to_id: record.handed_to_id, handed_to: record.handed_to&.name)
    end
end
