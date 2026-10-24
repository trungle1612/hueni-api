require "test_helper"

class Admin::PaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12)
    # Thu 01/10 → Sat 03/10: Thu night 400k, Fri night 500k.
    @booking = rooms(:garden).bookings.create!(start_date: "2026-10-01", end_date: "2026-10-03", price: 400_000, weekend_price: 500_000, guests: 2, guest_name: "Chị Mai")
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
  end

  test "owners see the nights; payments lower Còn phải thu; Chuyển khoản shows the account and the code" do
    places(:tomo).update!(bank_name: "Vietcombank", bank_account: "0123456789", bank_holder: "NGUYEN THI LAN")
    log_in users(:owner)
    get edit_admin_booking_path(@booking)
    assert_select "#thanh-toan", text: /1 đêm × 400.000 ₫\s*400.000 ₫/
    assert_select "#thanh-toan", text: /1 đêm T6–T7 × 500.000 ₫/
    assert_select "#due", text: /Còn phải thu\s*900.000 ₫/
    assert_select "#ghi-nhan input[name='payment[amount]'][value='900.000']"
    assert_select "#bank", text: /Vietcombank · 0123456789.*NGUYEN THI LAN.*Nội dung: DP\d{4}/m

    post admin_booking_payments_path(@booking), params: { payment: { amount: "300k", payment_method: "bank", kind: "payment", note: "Cọc" } }
    assert_redirected_to edit_admin_booking_path(@booking, anchor: "thanh-toan")
    assert_equal "Đã thu 300.000 ₫ · Chuyển khoản.", flash[:notice]
    follow_redirect!
    assert_select "#thanh-toan", text: /Cọc · Chuyển khoản · 01\/10 · Chị Lan\s*−300.000 ₫/
    assert_select "#due", text: /Còn phải thu\s*600.000 ₫/

    post admin_booking_payments_path(@booking), params: { payment: { amount: "700k", payment_method: "cash", kind: "payment" } }
    assert_equal "Số tiền không được lớn hơn số còn phải thu (600.000 ₫)", flash[:alert]

    payment = @booking.payments.sole
    assert_difference -> { Payment.count }, -1 do
      delete admin_booking_payment_path(@booking, payment)
    end
    get admin_place_activity_path("tomo-homestay")
    assert_select "body", text: /Thu tiền.*300.000 ₫ · Chuyển khoản · DP-\d{4}/m
    assert_select "body", text: /Xoá khoản thu/
  end

  test "staff take money but see no nightly price; refunds and deleting are owners only; another homestay's booking is not found" do
    log_in @staff
    get edit_admin_booking_path(@booking)
    assert_select "#thanh-toan", text: /Tiền phòng\s*900.000 ₫/
    assert_select "#thanh-toan", text: /đêm ×/, count: 0
    assert_select "#ghi-nhan input[name='payment[kind]'][type=hidden][value=payment]"

    post admin_booking_payments_path(@booking), params: { payment: { amount: "900000", payment_method: "cash", kind: "payment" } }
    assert_equal 900_000, @booking.paid
    get edit_admin_booking_path(@booking)
    assert_select "#due", text: /Đã thu đủ/
    assert_select "#thanh-toan button[aria-label^='Xoá']", 0

    post admin_booking_payments_path(@booking), params: { payment: { amount: "1", payment_method: "cash", kind: "refund" } }
    assert_response :forbidden
    delete admin_booking_payment_path(@booking, @booking.payments.sole)
    assert_response :forbidden

    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06")
    post admin_booking_payments_path(other), params: { payment: { amount: "1", payment_method: "cash", kind: "payment" } }
    assert_response :not_found
  end

  test "Thu X và nhận phòng records the cash due; ghi nợ leaves it owed" do
    log_in users(:owner)
    get edit_admin_booking_path(@booking)
    assert_select "#stay button[name=collect][value='1']", "Thu 900.000 ₫ và nhận phòng"
    assert_select "#stay button", "Nhận phòng, ghi nợ"

    post check_in_admin_booking_path(@booking), params: { collect: "1" }
    assert_equal "Đã nhận phòng: Chị Mai · Garden · đã thu 900.000 ₫", flash[:notice]
    assert_equal [ 900_000, "cash" ], @booking.payments.sole.then { [ it.amount, it.payment_method ] }

    other = bookings(:limdim_confirmed).tap { it.update!(price: 400_000, guests: 2) }
    post check_in_admin_booking_path(other)
    assert_equal "Đã nhận phòng: Anh Minh · Limdim · còn nợ 800.000 ₫", flash[:notice]
    assert_empty other.payments
    post check_out_admin_booking_path(other), params: { collect: "1" }
    assert_match "đã thu 800.000 ₫", flash[:notice]
    assert_equal 0, other.reload.due
  end

  test "cancelling with money paid: owners keep or refund it, staff can only keep it" do
    @booking.payments.create!(amount: 300_000, payment_method: "cash", note: "Cọc")
    log_in @staff
    get edit_admin_booking_path(@booking)
    assert_select "#refund input[name=refund_method]", 1
    patch admin_booking_path(@booking), params: { booking: { status: "cancelled", cancel_reason: "Khách huỷ" }, refund_method: "cash" }
    assert @booking.reload.cancelled?
    assert_equal 300_000, @booking.paid

    @booking.update!(status: "confirmed")
    delete session_path
    log_in users(:owner)
    get edit_admin_booking_path(@booking)
    assert_select "#refund input[name=refund_method]", 1 + Payment::METHODS.size
    patch admin_booking_path(@booking), params: { booking: { status: "cancelled", cancel_reason: "Khách huỷ" }, refund_method: "bank" }
    assert_equal "Đã huỷ đặt phòng. Đã hoàn 300.000 ₫.", flash[:notice]
    assert_equal [ 0, "refund", "bank" ], [ @booking.reload.paid, *@booking.payments.last.then { [ it.kind, it.payment_method ] } ]
  end

  test "owners set the bank account on the homestay page; staff can't" do
    log_in users(:owner)
    patch bank_admin_place_path("tomo-homestay"), params: { place: { bank_name: " Vietcombank ", bank_account: "0123456789", bank_holder: "NGUYEN THI LAN" } }
    assert_redirected_to admin_place_path("tomo-homestay", anchor: "chuyen-khoan")
    assert_equal "Vietcombank", places(:tomo).reload.bank_name
    get admin_place_path("tomo-homestay")
    assert_select "#chuyen-khoan summary", text: /Vietcombank · 0123456789/

    delete session_path
    log_in @staff
    patch bank_admin_place_path("tomo-homestay"), params: { place: { bank_name: "x" } }
    assert_response :forbidden
    get admin_place_path("tomo-homestay")
    assert_select "#chuyen-khoan", 0
  end
end
