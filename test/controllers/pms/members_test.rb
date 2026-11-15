require "test_helper"

# Nhân viên và nhật ký in the PWA (#245): members, Chờ duyệt, Nhật ký; owners only.
class Pms::MembersTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123", zalo_id: "zalo-na")
    @membership = places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @owner_membership = place_memberships(:owner_tomo)
  end

  test "lists members owner first with role, activity and badges; linked from Thêm" do
    @staff.sessions.create!(updated_at: 1.day.ago.change(hour: 23, min: 10))
    log_in users(:owner)
    get pms_more_path
    assert_select "main a[href=?]", pms_members_path, text: /Nhân viên và nhật ký\s*2 tài khoản/
    get pms_members_path
    assert_response :success
    assert_select "header nav a[aria-current=page]", text: "Nhân viên"
    assert_select "h2", text: "2 tài khoản"
    assert_select "##{dom_id(@owner_membership)}", text: /Chị Lan\s*Chủ cơ sở · bạn/
    assert_select "##{dom_id(@membership)}", text: /Bé Na\s*Lễ tân · hoạt động hôm qua 23:10/
    assert_select "#sheet_#{dom_id(@owner_membership)}", text: /Đây là tài khoản của bạn/
    assert_select "#sheet_#{dom_id(@membership)} form[action=?]", setup_link_pms_member_path(@membership)
  end

  test "adds a staff member with rights and shows the Zalo link once; a used phone gets /admin's message" do
    log_in users(:owner)
    post pms_members_path, params: { member: { name: "Anh Tú", phone_number: "0911 222 333", role: "staff", permissions: [ "", "report" ] } }
    assert_redirected_to pms_members_path
    follow_redirect!
    membership = places(:tomo).place_memberships.joins(:user).find_by!(users: { name: "Anh Tú" })
    assert_equal [ "staff", %w[report], "0911222333" ], [ membership.role, membership.permissions, membership.user.phone_number ]
    assert_select ".pms-toast", text: "Đã thêm Anh Tú"
    assert_select "#link_sheet[data-controller~=open]", text: /Gửi link cho Anh Tú/
    assert_select "#link_sheet input[value*='/dat-mat-khau/']"
    assert_select "##{dom_id(membership)} .pms-badge", text: "Chờ nhận lời mời"
    get pms_members_path
    assert_select "#link_sheet", 0

    post pms_members_path, params: { member: { name: "X", phone_number: "0987654321", role: "staff" } }
    assert_response :unprocessable_entity
    assert_select "#member_sheet_new[data-controller=open] [role=alert]", text: PlaceMembership::PHONE_TAKEN
    assert_select "#member_sheet_new input[value='X']"
  end

  test "role and rights, lock and unlock, new link, remove; the last owner is kept" do
    log_in users(:owner)
    patch pms_member_path(@membership), params: { member: { role: "staff", permissions: [ "", "refund" ] } }
    follow_redirect!
    assert_select ".pms-toast", text: "Đã lưu quyền của Bé Na"
    assert_equal %w[refund], @membership.reload.permissions

    @staff.sessions.create!
    post lock_pms_member_path(@membership)
    assert @membership.reload.locked?
    assert_not Session.exists?(user: @staff)
    assert_not @staff.reload.accessible_places.include?(places(:tomo))
    follow_redirect!
    assert_select "##{dom_id(@membership)} .pms-badge", text: "Đã khoá"
    post unlock_pms_member_path(@membership)
    assert_not @membership.reload.locked?

    post setup_link_pms_member_path(@membership)
    assert_nil @staff.reload.zalo_id
    follow_redirect!
    assert_select "#link_sheet", text: /Gửi link cho Bé Na/

    post lock_pms_member_path(@owner_membership)
    follow_redirect!
    assert_select "[role=alert]", text: "Không khoá được chủ homestay."
    patch pms_member_path(@owner_membership), params: { member: { role: "staff" } }
    follow_redirect!
    assert_select "[role=alert]", text: PlaceMembership::LAST_OWNER
    delete pms_member_path(@owner_membership)
    assert @owner_membership.reload.owner?

    delete pms_member_path(@membership)
    follow_redirect!
    assert_select ".pms-toast", text: "Đã xoá Bé Na khỏi cơ sở"
    assert_not PlaceMembership.exists?(@membership.id)
  end

  test "an owner steps down, or leaves, when another owner stays" do
    @membership.update!(role: "owner")
    log_in users(:owner)
    patch pms_member_path(@owner_membership), params: { member: { role: "staff" } }
    assert_redirected_to pms_more_path
    @owner_membership.reload.update!(role: "owner")
    delete pms_member_path(@owner_membership)
    assert_redirected_to pms_today_path
    assert_not users(:owner).reload.accessible_places.exists?
  end

  test "Chờ duyệt: approve writes the refund, reject keeps the money" do
    rooms(:limdim).update!(price: 500_000)
    booking = rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-22", guest_name: "Chị Hoa")
    booking.payments.create!(amount: 400_000, payment_method: "cash")
    first = booking.refund_requests.create!(amount: 300_000, payment_method: "bank", note: "Khách về sớm", requested_by: @staff)
    second = booking.refund_requests.create!(amount: 50_000, payment_method: "cash", requested_by: @staff)
    log_in users(:owner)
    get pms_more_path
    assert_select "main a[href=?]", pms_members_path, text: /2 yêu cầu chờ duyệt/
    get pms_members_path
    assert_select "##{dom_id(first)}", text: /Xin hoàn 300.000đ · chuyển khoản\s*Bé Na gửi lúc hôm nay 10:00 · #{booking.code} Chị Hoa, phòng Limdim, đã thu 400.000đ. Lý do: Khách về sớm/

    post approve_pms_refund_request_path(first)
    follow_redirect!
    assert_select ".pms-toast", text: "Đã duyệt. Khoản hoàn 300.000đ được ghi vào #{booking.code}"
    assert_equal 100_000, booking.reload.paid
    post approve_pms_refund_request_path(first)
    follow_redirect!
    assert_select "[role=alert]", text: "Yêu cầu đã được xử lý"

    post reject_pms_refund_request_path(second)
    assert second.reload.rejected?
    follow_redirect!
    assert_select ".pms-toast", text: "Đã từ chối. Tiền giữ lại, ghi vào nhật ký"
    assert_select "[role=region]", 0
  end

  test "Nhật ký: this homestay only, filters, paged" do
    rooms(:limdim).update!(price: 450_000)
    other = rooms(:garden).dup.tap { it.update!(place: places(:hiuhill), name: "Ở cơ sở khác") }
    log_in users(:owner)
    get pms_activity_path
    assert_response :success
    assert_select "header nav a[aria-current=page]", text: "Nhật ký"
    assert_select "main", text: /Sửa phòng · phòng Limdim/
    assert_select "main", text: /Thêm thành viên|Bé Na/
    assert_select "main", text: /#{other.name}/, count: 0
    get pms_activity_path(filter: "money")
    assert_select "main", text: /Chưa có thao tác nào/
    get pms_activity_path(filter: "price")
    assert_select "[aria-current=page]", text: "Giá"
    assert_select "main", text: /Sửa phòng/
  end

  test "staff get Bạn chưa có quyền; another homestay's member and request are 404" do
    log_in @staff
    get pms_more_path
    assert_select "main a[href=?]", pms_members_path, count: 0
    get pms_members_path
    assert_response :forbidden
    assert_select "main", text: /Bạn chưa có quyền/
    get pms_activity_path
    assert_response :forbidden
    post pms_members_path, params: { member: { name: "X", phone_number: "0911222333", role: "staff" } }
    assert_response :forbidden
    [ [ :patch, pms_member_path(@owner_membership) ], [ :delete, pms_member_path(@owner_membership) ], [ :post, lock_pms_member_path(@membership) ],
      [ :post, setup_link_pms_member_path(@owner_membership) ] ].each do |verb, path|
      send(verb, path, params: { member: { role: "staff" } })
      assert_response :forbidden, path
    end

    other = places(:hiuhill).place_memberships.create!(user: User.create!(name: "Khác", phone_number: "0900000001", password: "password123"), role: "owner")
    booking = rooms(:garden).dup.tap { it.update!(place: places(:hiuhill), name: "H1") }.bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21")
    booking.payments.create!(amount: 100_000, payment_method: "cash")
    request = booking.refund_requests.create!(amount: 50_000, payment_method: "cash")
    log_in users(:owner)
    [ [ :patch, pms_member_path(other) ], [ :delete, pms_member_path(other) ], [ :post, lock_pms_member_path(other) ],
      [ :post, setup_link_pms_member_path(other) ], [ :post, approve_pms_refund_request_path(request) ] ].each do |verb, path|
      send(verb, path)
      assert_response :not_found, path
    end
    assert request.reload.pending?
  end
end
