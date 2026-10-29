require "test_helper"

# Nhân viên (#168, ADR-001): Quyền thêm, lock, invite, refund requests, Nhật ký filters.
class MiniApp::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    @booking = rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-22", guest_name: "Chị Hoa")
    @booking.payments.create!(amount: 400_000, payment_method: "cash")
    @owner = users(:owner)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123", zalo_id: "zalo-na")
    @membership = places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: @owner.api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: :json)
  def body = response.parsed_body

  test "Quyền thêm: staff discount by default; refund and report only once given" do
    as :staff, :patch, discount_api_v1_booking_path(@booking), { booking: { discount: "10%", discount_reason: "Khách quen" } }
    assert_response :success
    as :staff, :post, api_v1_booking_payments_path(@booking), { payment: { amount: 100_000, payment_method: "cash", kind: "refund" } }
    assert_response :forbidden
    as :staff, :get, report_api_v1_place_path(places(:tomo))
    assert_response :forbidden

    as :owner, :patch, api_v1_membership_path(@membership), { member: { permissions: %w[refund report] } }
    assert_response :success
    assert_equal %w[refund report], body.dig("member", "permissions")
    as :staff, :post, api_v1_booking_payments_path(@booking), { payment: { amount: 100_000, payment_method: "cash", kind: "refund" } }
    assert_response :created
    as :staff, :get, report_api_v1_place_path(places(:tomo))
    assert_response :success
    as :staff, :patch, discount_api_v1_booking_path(@booking), { booking: { discount: "" } }
    assert_response :forbidden

    as :owner, :patch, api_v1_membership_path(@membership), { member: { permissions: %w[fly] } }
    assert_response :unprocessable_entity
    line = Activity.lines(PaperTrail::Version.where(item_type: "PlaceMembership").order(:id).last(1)).sole
    assert_equal [ "Đổi quyền", "Bé Na: + Hoàn tiền không cần duyệt, + Xem báo cáo, − Giảm giá đến 10%" ], [ line.action, line.detail ]
  end

  test "lock: out of the homestay and logged out; owners can't be locked; unlock lets them back" do
    as :owner, :post, lock_api_v1_membership_path(@membership)
    assert_response :success
    assert body.dig("member", "locked")
    assert_empty @staff.api_tokens.reload
    @tokens[:staff] = @staff.api_tokens.create!.token
    as :staff, :get, today_api_v1_place_path(places(:tomo))
    assert_response :not_found
    as :staff, :get, api_v1_me_path
    assert_empty body["places"]

    as :owner, :post, lock_api_v1_membership_path(@owner.place_memberships.sole)
    assert_response :unprocessable_entity
    as :owner, :post, unlock_api_v1_membership_path(@membership)
    as :staff, :get, today_api_v1_place_path(places(:tomo))
    assert_response :success
    assert_equal [ "Mở khoá tài khoản", "Khoá tài khoản" ], Activity.lines(PaperTrail::Version.where(item_type: "PlaceMembership").order(id: :desc).first(2)).map(&:action)
  end

  test "invite by phone gives a one-time link; list, remove; the phone of an existing account is refused" do
    as :owner, :post, api_v1_place_memberships_path(places(:tomo)), { member: { name: "Anh Tú", phone_number: "0911 222 333", role: "staff", permissions: %w[report] } }
    assert_response :created
    assert_match %r{/dat-mat-khau/}, body["setup_link"]
    assert_equal [ "Anh Tú", "0911222333", %w[report], true ], body["member"].values_at("name", "phone", "permissions", "invited")

    as :owner, :post, api_v1_place_memberships_path(places(:tomo)), { member: { name: "X", phone_number: "0987654321", role: "staff" } }
    assert_response :unprocessable_entity

    as :owner, :get, api_v1_place_memberships_path(places(:tomo))
    assert_equal [ "Chị Lan", "Anh Tú", "Bé Na" ], body["members"].pluck("name")
    assert_equal false, body["members"].last["invited"]

    as :owner, :delete, api_v1_membership_path(@membership)
    assert_response :no_content
    as :owner, :post, setup_link_api_v1_membership_path(@owner.place_memberships.sole)
    assert_response :forbidden
  end

  test "refund requests: staff ask, the owner approves (the refund is written) or rejects; both logged" do
    as :staff, :post, api_v1_booking_refund_requests_path(@booking), { refund_request: { amount: "500k", payment_method: "cash" } }
    assert_response :unprocessable_entity
    as :staff, :post, api_v1_booking_refund_requests_path(@booking), { refund_request: { amount: "300k", payment_method: "bank", note: "Khách về sớm" } }
    assert_response :created
    first = body["id"]
    as :staff, :post, api_v1_booking_refund_requests_path(@booking), { refund_request: { amount: "50k", payment_method: "cash" } }
    second = body["id"]

    as :staff, :get, api_v1_place_refund_requests_path(places(:tomo))
    assert_response :forbidden
    as :owner, :get, api_v1_place_refund_requests_path(places(:tomo))
    assert_equal [ [ 300_000, "Bé Na", 400_000 ], [ 50_000, "Bé Na", 400_000 ] ], body["refund_requests"].map { [ it["amount"], it["by"], it.dig("booking", "paid") ] }

    as :owner, :post, approve_api_v1_refund_request_path(first)
    assert_response :success
    assert_equal "approved", body["status"]
    assert_equal [ -300_000, @staff ], @booking.payments.order(:id).last.then { [ it.signed_amount, it.user ] }
    as :owner, :post, approve_api_v1_refund_request_path(first)
    assert_response :unprocessable_entity
    as :owner, :post, reject_api_v1_refund_request_path(second)
    assert_equal "rejected", body["status"]
    assert_equal [ "Từ chối hoàn tiền", "Duyệt hoàn tiền", "Hoàn tiền" ], Activity.lines(PaperTrail::Version.where(place_id: places(:tomo).id).order(id: :desc).first(3)).map(&:action)

    as :owner, :get, activity_api_v1_place_path(places(:tomo), filter: "money")
    assert_equal [ "Từ chối hoàn tiền", "Duyệt hoàn tiền", "Hoàn tiền", "Xin hoàn tiền", "Xin hoàn tiền", "Thu tiền" ], body["activities"].pluck("action")
    as :owner, :get, activity_api_v1_place_path(places(:tomo), filter: "price")
    assert_equal [ "Sửa phòng" ], body["activities"].pluck("action")
  end

  test "another owner's homestay and members are 404; staff on owner-only actions are 403" do
    other = places(:hiuhill).place_memberships.create!(user: User.create!(name: "Khác", phone_number: "0900000001", password: "password123"), role: "owner")
    as :owner, :get, api_v1_place_memberships_path(places(:hiuhill))
    assert_response :not_found
    as :owner, :patch, api_v1_membership_path(other), { member: { role: "staff" } }
    assert_response :not_found
    as :owner, :post, lock_api_v1_membership_path(other)
    assert_response :not_found
    request = RefundRequest.create!(booking: places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21").tap { it.payments.create!(amount: 1_000, payment_method: "cash") }, amount: 1_000, payment_method: "cash")
    as :owner, :post, approve_api_v1_refund_request_path(request)
    assert_response :not_found

    as :staff, :get, api_v1_place_memberships_path(places(:tomo))
    assert_response :forbidden
    as :staff, :patch, api_v1_membership_path(@membership), { member: { permissions: %w[refund] } }
    assert_response :forbidden
    as :staff, :post, lock_api_v1_membership_path(@membership)
    assert_response :forbidden
  end
end
