require "test_helper"

# Thêm, Tài khoản, Điều khoản in the PWA (#236).
class Pms::MoreTest < ActionDispatch::IntegrationTest
  def staff!
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
  end

  test "owner: built screens only, homestay switcher, account with Điều khoản, Đăng xuất, Xoá tài khoản" do
    PlaceMembership.create!(user: users(:owner), place: places(:hiuhill), role: "staff")
    log_in users(:owner)
    patch pms_place_path("tomo-homestay")
    get pms_more_path
    assert_response :success
    assert_select "nav a[aria-current=page]", text: "Thêm"
    assert_select "header button[popovertarget=places_sheet]", text: /tomo homestay/
    assert_select "#places_sheet form[action=?] button", pms_place_path("hiuhill-homestay"), text: /Hiu Hill Homestay\s*Chọn/
    assert_select "main a[href=?]", pms_search_path, text: /Tìm đặt phòng/
    assert_select "main a[href=?]", pms_rooms_path, text: /Danh sách phòng\s*2 phòng/
    assert_select "main a", text: /Khai báo lưu trú|Giao ca|Buồng phòng|Kênh bán/, count: 0
    assert_select "#account", text: /Chị Lan\s*Chủ cơ sở · 0912345678/
    assert_select "#account a[href=?]", pms_legal_path, text: /Điều khoản và quyền riêng tư/
    assert_select "#account form[action=?] button", session_path, text: "Đăng xuất"
    assert_select "#delete_sheet", text: /Bạn là chủ duy nhất của tomo homestay/
    assert_select "#delete_sheet form[action=?] button", pms_account_path, text: "Xoá tài khoản"
  end

  test "staff: no owner setup, no sole-owner warning" do
    staff!
    get pms_more_path
    assert_select "main a[href=?]", pms_rooms_path, count: 0
    assert_select "#account", text: /Lễ tân/
    assert_select "#sole_owner", 0
  end

  test "Xoá tài khoản by staff anonymises them and keeps the homestay's bookings and payments" do
    staff!
    booking = bookings(:limdim_confirmed)
    booking.payments.create!(amount: 100_000, payment_method: "cash", user: users(:admin))
    assert_no_difference [ "Booking.count", "Payment.count" ] do
      delete pms_account_path
    end
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=status]", "Đã xoá tài khoản."
    admin = users(:admin).reload
    assert admin.deleted?
    assert_equal User::DELETED_NAME, admin.name
    assert_empty admin.place_memberships
    get pms_today_path
    assert_redirected_to new_session_path
  end

  test "Xoá tài khoản by the only owner clears that homestay's bookings, as DELETE /api/v1/me" do
    log_in users(:owner)
    delete pms_account_path
    assert_redirected_to new_session_path
    assert_equal 0, Booking.where(room: places(:tomo).rooms).count
    assert places(:tomo).reload.rooms.any?
  end

  test "Điều khoản: both texts, the version agreed to, support phone" do
    users(:owner).update!(terms_version: "2026-11-11", terms_accepted_at: Time.zone.local(2026, 11, 12, 20, 51))
    log_in users(:owner)
    get pms_legal_path
    assert_response :success
    assert_select "nav a[aria-current=page]", "Điều khoản sử dụng"
    assert_select "#summary li", 4
    assert_select "details summary", text: /Phạm vi và chấp nhận/
    assert_select "#consent", /Bạn đã đồng ý phiên bản 2026-11-11 lúc 20:51 ngày 12\/11\/2026/
    assert_select "a[href='tel:0794521276']"
    get pms_legal_path(doc: "privacy")
    assert_select "nav a[aria-current=page]", "Chính sách bảo mật"
    assert_select "details summary", text: /Quyền của bạn/

    staff!
    get pms_legal_path
    assert_select "#consent", /Chưa có ghi nhận/
  end
end
