require "test_helper"

class Admin::RegistrationRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registration = RegistrationRequest.create!(zalo_id: "zalo-hoa", zalo_name: "Hoa Zalo", name: "Hoa Nguyễn",
      phone_number: "0905123456", place: places(:hiuhill), place_name: "Hiu Hill Homestay")
    log_in users(:admin)
  end

  def choose(place: places(:hiuhill), note: "") = { registration_request: { place_id: place&.id, admin_note: note } }

  test "non-admins get 404 on every action and change nothing" do
    delete session_path
    log_in users(:owner)
    get admin_registration_request_path(@registration)
    assert_response :not_found
    patch admin_registration_request_path(@registration), params: choose(note: "x")
    assert_response :not_found
    patch approve_admin_registration_request_path(@registration), params: choose.merge(called: "1")
    assert_response :not_found
    patch reject_admin_registration_request_path(@registration), params: choose
    assert_response :not_found
    assert @registration.reload.pending?
    assert_nil @registration.admin_note
  end

  test "request page shows the requester, the homestay's hueni phone to call and that it has no owner" do
    places(:hiuhill).update!(phone: "0234 3 812 345")
    get admin_registration_request_path(@registration)
    assert_select "#requester", text: /Hoa Nguyễn.*Hoa Zalo.*0905 123 456.*chưa xác minh/m
    assert_select "#homestay a[href=?]", "tel:02343812345"
    assert_select "#homestay", text: /Chưa có chủ/
    assert_select "input[type=checkbox][name=called][required]"
    assert_select "input[type=submit][value=?]", "Tạo tài khoản"
  end

  test "a homestay with an owner offers only Từ chối" do
    @registration.update!(place: places(:tomo))
    get admin_registration_request_path(@registration)
    assert_select "#homestay", text: /Đã có chủ: Chị Lan/
    assert_select "body", text: /nhờ chủ hiện tại thêm ở mục Thành viên/
    assert_select "input[type=submit][value^=?]", "Tạo tài khoản", 0
    assert_select "input[type=submit][value=?]", "Từ chối"
  end

  test "approving needs the call confirmed, then creates the Zalo-linked owner" do
    patch approve_admin_registration_request_path(@registration), params: choose
    assert_redirected_to admin_registration_request_path(@registration)
    assert_equal "Gọi xác nhận trước khi tạo tài khoản.", flash[:alert]
    assert @registration.reload.pending?

    assert_difference -> { User.count }, 1 do
      patch approve_admin_registration_request_path(@registration), params: choose(note: "Đã gọi").merge(called: "1")
    end
    user = User.find_by!(zalo_id: "zalo-hoa")
    assert_redirected_to edit_admin_user_path(user)
    assert_equal "Đã tạo tài khoản cho Hoa Nguyễn. Hãy báo người này đăng nhập bằng Zalo.", flash[:notice]
    assert_equal "owner", user.role_at(places(:hiuhill))
    assert_equal [ "approved", "Đã gọi" ], [ @registration.reload.status, @registration.admin_note ]
  end

  test "choosing an owned homestay and approving fails and creates nothing" do
    assert_no_difference -> { User.count } do
      patch approve_admin_registration_request_path(@registration), params: choose(place: places(:tomo)).merge(called: "1")
    end
    assert_equal "tomo homestay vừa có chủ. Không tạo tài khoản.", flash[:alert]
    assert @registration.reload.pending?
  end

  test "saving picks a homestay for an unlisted request and keeps a note" do
    @registration.update!(place: nil, place_name: "Nhà Mơ Kim Long")
    get admin_registration_request_path(@registration)
    assert_select "#homestay", text: /Nhà Mơ Kim Long.*chưa có trên hueni/m
    patch admin_registration_request_path(@registration), params: choose(note: "Gọi lại chiều")
    assert_redirected_to admin_registration_request_path(@registration)
    assert_equal [ places(:hiuhill), "Gọi lại chiều" ], [ @registration.reload.place, @registration.admin_note ]
  end

  test "rejecting keeps the request as history" do
    patch reject_admin_registration_request_path(@registration), params: choose(note: "Không phải chủ")
    assert_redirected_to admin_users_path
    assert_equal [ "rejected", users(:admin), "Không phải chủ" ], [ @registration.reload.status, @registration.decided_by, @registration.admin_note ]

    patch approve_admin_registration_request_path(@registration), params: choose.merge(called: "1")
    assert_equal "Yêu cầu đã được xử lý.", flash[:alert]
    get admin_registration_request_path(@registration)
    assert_select "form", text: /Tạo tài khoản/, count: 0
    assert_select "body", text: /Đã từ chối bởi Trung/
  end

  test "Người dùng lists pending requests; the menu and Tổng quan show the count" do
    get admin_users_path
    assert_select "#registrations a[href=?]", admin_registration_request_path(@registration)
    assert_select "aside a", text: /Người dùng \(1\)/
    get admin_root_path
    assert_select "#pending_registrations", text: /1 yêu cầu đăng ký chờ duyệt/

    @registration.update!(status: "rejected")
    get admin_users_path
    assert_select "#registrations", 0
    assert_select "#decided_registrations", text: /Hoa Nguyễn/
    assert_select "aside a", text: /Người dùng \(/, count: 0
  end
end
