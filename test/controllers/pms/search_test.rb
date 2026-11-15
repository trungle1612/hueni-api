require "test_helper"

# Tìm đặt phòng in the PWA (#235): Booking.search_sections over the user's homestays.
class Pms::SearchTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 10, 12)
    @in = rooms(:garden).bookings.create!(start_date: "2026-10-09", end_date: "2026-10-12", guest_name: "Chị Mái", guest_phone: "+84 905 123 456")
    @in.update_columns(checked_in_at: 1.day.ago)
    @soon = rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-22", guest_name: "Anh Mai Đức")
    @gone = rooms(:limdim).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06", guest_name: "Bà Mai")
    @gone.update_columns(checked_in_at: 5.days.ago, checked_out_at: 4.days.ago)
    @cancelled = rooms(:garden).bookings.create!(start_date: "2026-10-25", end_date: "2026-10-26", guest_name: "Cô Mai", status: "cancelled", cancel_reason: "Khách huỷ")
    @other = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21", guest_name: "Chị Mai Khác")
  end

  test "a name without diacritics finds every Mai of your homestays, grouped, each opening Chi tiết" do
    log_in users(:owner)
    get pms_today_path
    assert_select "a[href=?][aria-label='Tìm đặt phòng']", pms_search_path

    get pms_search_path(q: " mai ")
    assert_response :success
    assert_select "input[name=q][value=mai]"
    assert_select "main", text: /4 đặt phòng/
    assert_select "#in_house a[href=?]", pms_booking_path(@in), text: /Chị Mái\s*#{@in.code} · Phòng Garden · 09 – 12\/10\s*Đang ở/
    assert_select "#upcoming a[href=?]", pms_booking_path(@soon), text: /Sắp đến/
    assert_select "#past", text: /Cô Mai.*Đã huỷ.*Bà Mai.*Đã trả/m
    assert_select "body", text: /Mai Khác/, count: 0

    get pms_search_path(q: "0905 123")
    assert_select "[id^=search_booking]", 1
    get pms_search_path(q: @soon.code)
    assert_select "##{dom_id(@soon, :search)}"
  end

  test "staff search too; empty, too short and no match say so" do
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
    get pms_search_path
    assert_response :success
    assert_select "p", text: /Gõ tên có dấu hoặc không dấu/
    get pms_search_path(q: "m")
    assert_select "p", "Nhập ít nhất 2 ký tự."
    get pms_search_path(q: "zzz")
    assert_select "#no_results", text: /Không có đặt phòng khớp “zzz”/
    assert_select "#no_results a[href=?]", new_pms_booking_path, text: "+ Đặt phòng mới"
    get pms_search_path(q: "mai")
    assert_select "[id^=search_booking]", 4
  end

  test "another homestay's booking is neither found nor opened" do
    log_in users(:owner)
    get pms_search_path(q: "Mai Khác")
    assert_select "#no_results"
    get pms_booking_path(@other)
    assert_response :not_found
  end
end
