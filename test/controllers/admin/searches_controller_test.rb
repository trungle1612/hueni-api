require "test_helper"

# Tìm đặt phòng (#143).
class Admin::SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 10, 12)
    @in = rooms(:garden).bookings.create!(start_date: "2026-10-09", end_date: "2026-10-12", guest_name: "Chị Mái", guest_phone: "+84 905 123 456")
    @in.update_columns(checked_in_at: 1.day.ago)
    @soon = rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-22", guest_name: "Anh Mai Đức")
    @gone = rooms(:limdim).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06", guest_name: "Bà Mai")
    @gone.update_columns(checked_in_at: 5.days.ago, checked_out_at: 4.days.ago)
    @cancelled = rooms(:garden).bookings.create!(start_date: "2026-10-25", end_date: "2026-10-26", guest_name: "Cô Mai", status: "cancelled", cancel_reason: "Khách huỷ")
    places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21", guest_name: "Chị Mai Khác")
  end

  test "a name without diacritics finds every Mai, grouped Đang ở · Sắp đến · Đã qua và đã huỷ, only your homestays" do
    log_in users(:owner)
    get admin_search_path(q: "mai")
    assert_response :success
    assert_select "#in_house a[href=?]", edit_admin_booking_path(@in), text: /Chị Mái · \+84 905 123 456/
    assert_select "#upcoming", text: /Anh Mai Đức/
    assert_select "#past", text: /Cô Mai.*Đã huỷ · Khách huỷ.*Bà Mai.*Đã trả phòng/m
    assert_select "body", text: /Mai Khác/, count: 0
    get admin_search_path(q: "ĐỨC")
    assert_select "[id^=search_booking]", 1
  end

  test "phone in any format; code as DP-0004, dp4 or 0004" do
    log_in users(:owner)
    [ "0905123456", "0905 123", "+84905123456" ].each do |q|
      get admin_search_path(q:)
      assert_select "[id^=search_booking]", 1, q
    end
    @soon.update_column(:number, 99)
    [ "DP-0099", "dp99", "0099", "99" ].each do |q|
      get admin_search_path(q:)
      assert_select "#search_booking_#{@soon.id}", 1, q
    end
  end

  test "staff search too; nothing found offers a new booking; the query stays out of the logs" do
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    log_in staff
    get admin_search_path(q: "mái")
    assert_select "[id^=search_booking]", 4
    get admin_search_path(q: "Không ai")
    assert_select "#no_results a[href=?]", new_admin_place_booking_path("tomo-homestay"), text: "+ Đặt phòng mới"
    get admin_search_path
    assert_select "[id^=search_booking]", 0
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal({ "q" => "[FILTERED]", "quantity" => "2" }, filter.filter("q" => "Chị Mai", "quantity" => "2"))
  end
end
