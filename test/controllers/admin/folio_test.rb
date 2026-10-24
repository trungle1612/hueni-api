require "test_helper"

# Dịch vụ and Giảm giá on a booking's bill (#140).
class Admin::FolioTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12)
    # Thu 01/10 → Sat 03/10 at 400k a night: 800k.
    @booking = rooms(:garden).bookings.create!(start_date: "2026-10-01", end_date: "2026-10-03", price: 400_000, guests: 2, guest_name: "Chị Mai")
    @water = places(:tomo).services.create!(name: "Nước suối", price: "15k", unit: "chai")
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
  end

  test "staff add a service from the catalog; it is copied, counted in Còn phải thu and removable" do
    log_in @staff
    get edit_admin_booking_path(@booking)
    assert_select "#them-dich-vu select[name=service_id] option", "Nước suối · 15.000 ₫/chai"

    post admin_booking_charges_path(@booking), params: { service_id: @water.id, quantity: "2" }
    assert_equal "Đã thêm Nước suối × 2 chai.", flash[:notice]
    @water.update!(price: 20_000)
    assert_equal [ 830_000, 830_000 ], [ @booking.total, @booking.due ]
    get edit_admin_booking_path(@booking)
    assert_select "#thanh-toan", text: /Nước suối · 2 chai × 15.000 ₫\s*30.000 ₫/
    assert_select "#thanh-toan", text: /Tổng\s*830.000 ₫/

    other = places(:hiuhill).services.create!(name: "Xe đạp", price: 50_000)
    post admin_booking_charges_path(@booking), params: { service_id: other.id }
    assert_response :not_found

    post admin_booking_charges_path(@booking), params: { service_id: @water.id, quantity: "1" }
    delete admin_booking_charge_path(@booking, @booking.charges.last)
    delete admin_booking_charge_path(@booking, @booking.charges.sole)
    assert_equal "Đã bỏ Nước suối × 2 chai.", flash[:notice]
    assert_equal 800_000, @booking.reload.total

    delete session_path
    log_in users(:owner)
    get admin_place_activity_path("tomo-homestay")
    assert_select "body", text: /Thêm dịch vụ.*Nước suối × 2 chai · 30.000 ₫ · DP-\d{4}/m
    assert_select "body", text: /Bỏ dịch vụ/
    get edit_admin_booking_path(@booking)
    assert_select "#history", text: /Bỏ dịch vụ.*Thêm dịch vụ · Nước suối × 1 chai · 20.000 ₫.*Đặt phòng/m
  end

  test "Giảm giá: an amount or %, with a reason, never above the room; staff at most 10%" do
    log_in @staff
    patch discount_admin_booking_path(@booking), params: { booking: { discount: "10%", discount_reason: "Khách quen" } }
    assert_equal "Đã giảm 80.000 ₫.", flash[:notice]
    assert_equal [ 80_000, "Khách quen", 720_000 ], @booking.reload.then { [ it.discount, it.discount_reason, it.due ] }

    patch discount_admin_booking_path(@booking), params: { booking: { discount: "100k", discount_reason: "Khách quen" } }
    assert_equal "Giảm giá nhân viên giảm tối đa 10% tiền phòng (80.000 ₫)", flash[:alert]
    patch discount_admin_booking_path(@booking), params: { booking: { discount: "50k", discount_reason: "" } }
    assert_equal "Lý do giảm giá không thể để trống", flash[:alert]

    delete session_path
    log_in users(:owner)
    patch discount_admin_booking_path(@booking), params: { booking: { discount: "900k", discount_reason: "Đền bù" } }
    assert_equal "Giảm giá không được lớn hơn tiền phòng (800.000 ₫)", flash[:alert]
    patch discount_admin_booking_path(@booking), params: { booking: { discount: "200.000", discount_reason: "Đền bù" } }
    assert_equal 200_000, @booking.reload.discount
    get edit_admin_booking_path(@booking)
    assert_select "#discount", text: /Giảm giá · Đền bù\s*−200.000 ₫/
    get admin_place_activity_path("tomo-homestay")
    assert_select "body", text: /giảm giá 80.000 ₫ → 200.000 ₫ \(Đền bù\)/

    patch discount_admin_booking_path(@booking), params: { booking: { discount: "", discount_reason: "Đền bù" } }
    assert_equal "Đã bỏ giảm giá.", flash[:notice]
    assert_equal [ nil, nil ], @booking.reload.then { [ it.discount, it.discount_reason ] }
  end

  test "owners manage the catalog on the homestay page; new homestays start with the defaults; staff can't" do
    assert_equal Service::DEFAULTS.map(&:first).sort, Place.create!(slug: "moi", name: "Mới").services.map(&:name).sort

    log_in users(:owner)
    get admin_place_path("tomo-homestay")
    assert_select "#dich-vu summary", text: /1 dịch vụ/
    post admin_place_services_path("tomo-homestay"), params: { service: { name: " Giặt ủi ", price: "30k", unit: "kg" } }
    assert_redirected_to admin_place_path("tomo-homestay", anchor: "dich-vu")
    assert_equal [ 30_000, "kg" ], places(:tomo).services.find_by!(name: "Giặt ủi").then { [ it.price, it.unit ] }
    post admin_place_services_path("tomo-homestay"), params: { service: { name: "nước SUỐI", price: "1" } }
    assert_equal "Tên dịch vụ đã tồn tại", flash[:alert]
    patch admin_place_service_path("tomo-homestay", @water), params: { service: { name: "Nước suối", price: "12k", unit: "chai" } }
    assert_equal 12_000, @water.reload.price
    delete admin_place_service_path("tomo-homestay", @water)
    assert_not Service.exists?(@water.id)
    get admin_place_activity_path("tomo-homestay")
    assert_select "body", text: /Thêm vào danh sách dịch vụ.*Giặt ủi · 30.000 ₫\/kg/m
    assert_select "body", text: /Sửa dịch vụ.*Nước suối: giá 15.000 ₫ → 12.000 ₫/m
    assert_select "body", text: /Xoá khỏi danh sách dịch vụ.*Nước suối · 12.000 ₫\/chai/m
    assert_equal 0, PaperTrail::Version.where(item_type: "Service", place_id: Place.find_by!(slug: "moi").id).count

    delete session_path
    log_in @staff
    post admin_place_services_path("tomo-homestay"), params: { service: { name: "X", price: "1" } }
    assert_response :forbidden
  end
end
