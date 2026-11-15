require "test_helper"

# Thông báo in the PWA (#237): the current homestay's inbox for owners and staff, read marks, settings.
class Pms::NotificationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    travel_to Time.zone.local(2026, 11, 8, 14, 0)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    booking = rooms(:limdim).bookings.create!(start_date: "2026-11-20", end_date: "2026-11-22", guest_name: "Chị Hoa", price: 300_000)
    booking.payments.create!(amount: 300_000, payment_method: "bank")
    perform_enqueued_jobs
    @booking_note, @payment_note = Notification.order(:id).last(2)
    @feed = calendar_feeds(:limdim_airbnb)
    @feed.update_columns(last_error: "RuntimeError: HTTP 404", last_error_at: 1.hour.ago)
  end

  def keys = css_select("a[id^=notification_]").map { it["id"].delete_prefix("notification_") }

  test "the inbox: groups, filters, money for owners only, Đọc hết with Hoàn tác" do
    log_in users(:owner)
    get pms_today_path
    assert_select "a[href=?][aria-label=?]", pms_notifications_path, "Thông báo, 3 chưa đọc"

    get pms_notifications_path
    assert_response :success
    assert_select "header", text: /3 chưa đọc · tomo homestay/
    assert_select "section[aria-label='Hôm nay'] #notification_n#{@payment_note.id}", text: /Thu tiền\s*300.000 ₫ · Chuyển khoản/
    assert_equal [ "n#{@payment_note.id}", "n#{@booking_note.id}", "f#{@feed.id}-#{@feed.last_error_at.to_i}" ], keys
    get pms_notifications_path(loc: "can-xu-ly")
    assert_equal [ "f#{@feed.id}-#{@feed.last_error_at.to_i}" ], keys

    post pms_read_all_notifications_path(loc: "chua-doc")
    assert_redirected_to pms_notifications_path(loc: "chua-doc")
    follow_redirect!
    assert_select ".pms-toast", text: /Đã đánh dấu 3 thông báo là đã đọc/
    assert_select "header", text: /Đã đọc hết/
    assert_select "div", text: /Không có thông báo chưa đọc/
    at = css_select(".pms-toast input[name=at]").first["value"]
    post pms_undo_read_notifications_path, params: { at:, loc: "chua-doc" }
    follow_redirect!
    assert_equal 3, keys.size

    log_in @staff
    get pms_notifications_path
    assert_equal [ "n#{@booking_note.id}", "f#{@feed.id}-#{@feed.last_error_at.to_i}" ], keys # Thu tiền is owners only
  end

  test "a tap marks it read and opens it; another homestay's key opens nothing" do
    log_in @staff
    get pms_open_notification_path("n#{@booking_note.id}")
    assert_redirected_to pms_booking_path(@booking_note.booking_id)
    assert @staff.notification_reads.exists?(key: "n#{@booking_note.id}")

    get pms_open_notification_path("n#{@payment_note.id}") # owners only
    assert_redirected_to pms_notifications_path
    assert_not @staff.notification_reads.exists?(key: "n#{@payment_note.id}")

    other = Notification.create!(place: places(:hiuhill), kind: "booking", title: "Đặt phòng mới", source: "Hệ thống", created_at: Time.current)
    get pms_open_notification_path("n#{other.id}")
    assert_redirected_to pms_notifications_path
    assert_not @staff.notification_reads.exists?(key: "n#{other.id}")

    announcement = Announcement.create!(kind: "maintenance", title: "Bảo trì 02:00", summary: "Tạm ngưng 30 phút", content: "## Bị ảnh hưởng\n- Không đồng bộ", published_at: 1.hour.ago)
    get pms_open_notification_path("a#{announcement.id}")
    assert_redirected_to pms_notifications_path(xem: "a#{announcement.id}")
    follow_redirect!
    assert_select "#announcement_sheet[data-controller=open]", text: /BẢO TRÌ HỆ THỐNG\s*Bảo trì 02:00.*Bị ảnh hưởng\s*Không đồng bộ.*Đã hiểu/m
  end


  test "Cài đặt thông báo: types off except channel" do
    log_in @staff
    patch pms_notification_settings_path, params: { on: [ "", "money", "channel" ] }
    assert_redirected_to pms_notifications_path("cai-dat": 1)
    assert_equal Notification::OPTIONAL - %w[money], @staff.reload.notifications_off
    follow_redirect!
    assert_select "#settings_sheet[data-controller=open] input#on_money[checked]"
    assert_select "#settings_sheet input#on_book:not([checked])"
    assert_select "#settings_sheet input#on_channel[checked][disabled]"
    assert_equal [ "f#{@feed.id}-#{@feed.last_error_at.to_i}" ], keys # Đặt phòng mới turned off; lỗi kênh can't be
  end
end
