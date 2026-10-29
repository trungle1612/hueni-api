require "test_helper"

# Giao ca (#167).
class MiniApp::ShiftsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    @booking = rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-22", guest_name: "Chị Hoa")
    @owner = users(:owner)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: @owner.api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: :json)
  def body = response.parsed_body

  test "expected cash = opening + cash payments − cash refunds − expenses since the last close" do
    @booking.payments.create!(amount: 600_000, payment_method: "cash")
    @booking.payments.create!(amount: 100_000, payment_method: "cash", kind: "refund")
    @booking.payments.create!(amount: 300_000, payment_method: "bank")
    as :staff, :post, cash_expenses_api_v1_place_path(places(:tomo)), { expense: { amount: "150k", reason: "Mua nước suối" } }
    assert_response :created
    assert_equal [ 0, 600_000, 100_000, 150_000, 350_000 ], body.values_at("opening", "cash_in", "cash_out", "expenses_total", "expected")
    assert_equal({ "bank" => 300_000, "card" => 0 }, body["other"])
    assert_equal "Bé Na", body["expenses"].sole["by"]

    as :staff, :post, close_shift_api_v1_place_path(places(:tomo)), { shift_close: { denominations: { "200000" => 1, "100000" => 1, "50000" => 1 }, keep: 100_000, handed_to_id: @owner.id } }
    assert_response :created
    assert_equal [ 350_000, 350_000, 0, "Chị Lan" ], body["close"].values_at("expected", "counted", "difference", "handed_to")
    assert_equal [ 100_000, 100_000, 0 ], body["shift"].values_at("opening", "expected", "expenses_total")

    travel 1.hour
    @booking.payments.create!(amount: 50_000, payment_method: "cash")
    as :staff, :get, shift_api_v1_place_path(places(:tomo))
    assert_equal [ 100_000, 50_000, 150_000 ], body.values_at("opening", "cash_in", "expected")
    assert_equal 350_000, body.dig("last_close", "counted")
  end

  test "a difference needs a note, shows on the owner's Hôm nay and in Hoạt động; keep ≤ counted" do
    as :staff, :post, close_shift_api_v1_place_path(places(:tomo)), { shift_close: { counted: 0, keep: 10_000 } }
    assert_response :unprocessable_entity
    assert body.dig("errors", "keep").present?

    @booking.payments.create!(amount: 500_000, payment_method: "cash")
    as :staff, :post, close_shift_api_v1_place_path(places(:tomo)), { shift_close: { counted: "450k", keep: 0 } }
    assert_response :unprocessable_entity
    assert_match "cần ghi lý do", body.dig("errors", "note").sole

    as :staff, :post, close_shift_api_v1_place_path(places(:tomo)), { shift_close: { counted: "450k", keep: 0, note: "Thối nhầm cho khách" } }
    assert_response :created
    assert_equal(-50_000, body.dig("close", "difference"))

    as :owner, :get, today_api_v1_place_path(places(:tomo))
    assert_equal [ [ -50_000, "Thối nhầm cho khách", "Bé Na" ] ], body["cash_differences"].map { it.values_at("difference", "note", "by") }
    as :staff, :get, today_api_v1_place_path(places(:tomo))
    assert_nil body["cash_differences"]
    line = Activity.lines(PaperTrail::Version.where(item_type: "ShiftClose").to_a).sole
    assert_equal [ "Chốt ca lệch", "Thiếu 50.000 ₫ · Thối nhầm cho khách", "Bé Na" ], [ line.action, line.detail, line.actor ]
  end

  test "an expense: its author or an owner changes it until the close; others get 403" do
    as :owner, :post, cash_expenses_api_v1_place_path(places(:tomo)), { expense: { amount: 100_000, reason: "Ga trải giường" } }
    expense = CashExpense.last
    as :staff, :patch, api_v1_cash_expense_path(expense), { expense: { amount: 1 } }
    assert_response :forbidden

    as :staff, :post, cash_expenses_api_v1_place_path(places(:tomo)), { expense: { amount: 20_000, reason: "Xăng" } }
    mine = CashExpense.last
    as :staff, :patch, api_v1_cash_expense_path(mine), { expense: { amount: 30_000 } }
    assert_response :success
    as :owner, :delete, api_v1_cash_expense_path(mine)
    assert_response :success
    assert_equal [ 100_000 ], body["expenses"].pluck("amount")
    as :owner, :post, cash_expenses_api_v1_place_path(places(:tomo)), { expense: { amount: 0, reason: "" } }
    assert body["errors"].keys.sort == %w[amount reason]

    travel 1.minute
    as :owner, :post, close_shift_api_v1_place_path(places(:tomo)), { shift_close: { counted: 0, keep: 0, note: "Chi hết" } }
    as :owner, :delete, api_v1_cash_expense_path(expense)
    assert_response :unprocessable_entity
    assert_match "Ca đã chốt", body.dig("errors", "base").sole
  end

  test "another owner's homestay and expenses are 404" do
    other = places(:hiuhill).cash_expenses.create!(amount: 1_000, reason: "X")
    as :owner, :get, shift_api_v1_place_path(places(:hiuhill))
    assert_response :not_found
    as :owner, :post, close_shift_api_v1_place_path(places(:hiuhill)), { shift_close: { counted: 0, keep: 0 } }
    assert_response :not_found
    as :owner, :post, cash_expenses_api_v1_place_path(places(:hiuhill)), { expense: { amount: 1_000, reason: "X" } }
    assert_response :not_found
    as :owner, :delete, api_v1_cash_expense_path(other)
    assert_response :not_found
    as :owner, :post, close_shift_api_v1_place_path(places(:tomo)), { shift_close: { counted: 0, keep: 0, handed_to_id: User.create!(name: "Lạ", phone_number: "0911222333", password: "password123").id } }
    assert body.dig("errors", "handed_to").present?
  end
end
