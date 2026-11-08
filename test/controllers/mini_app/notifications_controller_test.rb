require "test_helper"

# Thông báo (#213): what others did at the homestay, Cần xử lý and announcements; read marks and settings per user.
class MiniApp::NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 11, 8, 21, 30)
    @owner = users(:owner)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: @owner.api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
    PaperTrail.request(whodunnit: @staff.id.to_s) do
      @booking = rooms(:limdim).bookings.create!(start_date: "2026-11-08", end_date: "2026-11-10", guest_name: "Chị Hoa")
      @booking.payments.create!(amount: 300_000, payment_method: "bank")
      @booking.check_in(guests: 2)
      @refund = @booking.refund_requests.create!(amount: 100_000, payment_method: "cash", requested_by: @staff)
    end
    PaperTrail.request(whodunnit: @owner.id.to_s) do
      rooms(:garden).bookings.create!(start_date: "2026-11-20", end_date: "2026-11-21", guest_name: "Anh Tú")
    end
    calendar_feeds(:limdim_airbnb).update!(last_error: "404 Not Found", last_error_at: 1.hour.ago)
    @news = Announcement.create!(kind: "feature", title: "Xuất hoá đơn điện tử", summary: "Ngay từ Phiếu tính tiền.", content: "## Có gì mới\n- Một", published_at: 2.hours.ago)
    Announcement.create!(kind: "maintenance", title: "Cũ", summary: "Quá 30 ngày", published_at: 31.days.ago)
  end

  def as(who, method, path, **params) = send(method, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" })
  def body = response.parsed_body
  def inbox(who) = as(who, :get, api_v1_place_notifications_path(places(:tomo))).then { body }

  test "owner: others' bookings, money and requests, Cần xử lý, announcements; never their own actions" do
    result = inbox(:owner)
    assert_response :success
    titles = result["notifications"].pluck("title")
    assert_includes titles, "Đặt phòng mới"
    assert_includes titles, "Thu tiền"
    assert_includes titles, "Yêu cầu hoàn tiền chờ bạn duyệt"
    assert_not_includes titles, "Cũ"
    assert_equal 1, titles.count("Đặt phòng mới") # Anh Tú's is the owner's own

    booking = result["notifications"].find { it["title"] == "Đặt phòng mới" }
    assert_equal({ "type" => "book", "icon" => "book", "source" => "Bé Na", "urgent" => false, "unread" => true,
                   "link" => { "screen" => "booking", "id" => @booking.id } }, booking.slice("type", "icon", "source", "urgent", "unread", "link"))
    assert_match "Chị Hoa", booking["body"]
    assert_equal({ "screen" => "booking", "id" => @booking.id }, result["notifications"].find { it["title"] == "Thu tiền" }["link"])

    feed = result["notifications"].find { it["title"] == "Airbnb không đồng bộ được" }
    assert_equal [ "channel", true, { "screen" => "channels" } ], feed.values_at("type", "urgent", "link")
    assert_not_includes feed["body"], "404" # the person-facing message, never the raw error

    reminders = result["notifications"].select { it["type"] == "reg" }
    assert_equal [ "r2026110821", "r2026110808" ], reminders.pluck("key")
    assert_equal "1 đặt phòng chưa khai báo lưu trú", reminders.first["title"]

    news = result["notifications"].find { it["key"] == "a#{@news.id}" }
    assert_equal [ "news", "info", "TÍNH NĂNG MỚI · 08/11/2026", [ { "h" => "Có gì mới", "ordered" => false, "items" => [ "Một" ] } ] ],
      [ news["type"], news["tone"], news.dig("announcement", "kicker"), news.dig("announcement", "blocks") ]

    urgent = result["notifications"].select { it["urgent"] }.pluck("title")
    assert_equal 4, urgent.size, urgent.inspect # 2 reminders, feed, pending refund
    assert_equal [ result["notifications"].size, 4 ], result.values_at("unread", "action")
  end

  test "staff: no money or approvals, but the owner's booking" do
    titles = inbox(:staff)["notifications"].pluck("title")
    assert_equal [ "Đặt phòng mới" ], titles.grep(/Đặt phòng|Thu tiền|hoàn tiền/)
    assert inbox(:staff)["notifications"].find { it["title"] == "Đặt phòng mới" }["body"].include?("Anh Tú")
  end

  test "a resolved refund request is no longer urgent" do
    @refund.reject(@owner)
    item = inbox(:owner)["notifications"].find { it["title"] == "Yêu cầu hoàn tiền chờ bạn duyệt" }
    assert_equal false, item["urgent"]
  end

  test "read marks are per user; unread undoes Đọc hết" do
    keys = inbox(:owner)["notifications"].pluck("key")
    as :owner, :post, read_api_v1_place_notifications_path(places(:tomo)), keys: keys
    assert_response :no_content
    assert_equal [ 0, 0 ], inbox(:owner).values_at("unread", "action")
    assert_operator inbox(:staff)["unread"], :>, 0

    as :owner, :post, read_api_v1_place_notifications_path(places(:tomo)), keys: keys # twice is fine
    assert_response :no_content

    as :owner, :post, unread_api_v1_place_notifications_path(places(:tomo)), keys: keys.first(2)
    assert_equal 2, inbox(:owner)["unread"]
  end

  test "settings hide optional types; Trùng phòng và lỗi kênh stays on" do
    assert_equal [ "room" ], @owner.notifications_off
    as :owner, :patch, notifications_api_v1_me_path, off: %w[book news channel nope]
    assert_response :no_content
    assert_equal %w[book news], @owner.reload.notifications_off
    types = inbox(:owner)["notifications"].pluck("type").uniq
    assert_not_includes types, "book"
    assert_not_includes types, "news"
    assert_includes types, "channel"

    as :owner, :get, api_v1_me_path
    assert_equal %w[book news], body.dig("user", "notifications_off")
  end

  test "another owner's homestay 404" do
    as :owner, :get, api_v1_place_notifications_path(places(:hiuhill))
    assert_response :not_found
    as :owner, :post, read_api_v1_place_notifications_path(places(:hiuhill)), keys: [ "v1" ]
    assert_response :not_found
  end

  test "prune drops read marks older than the inbox" do
    NotificationRead.mark(@owner, %w[v1])
    travel 32.days
    NotificationRead.mark(@owner, %w[v2])
    NotificationRead.prune
    assert_equal %w[v2], @owner.notification_reads.pluck(:key)
  end
end
