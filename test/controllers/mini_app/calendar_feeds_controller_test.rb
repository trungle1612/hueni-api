require "test_helper"

# Mini App Kênh OTA: feed status and Đồng bộ ngay (#157).
class MiniApp::CalendarFeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 5, 12)
    @feed = rooms(:limdim).calendar_feeds.create!(url: "https://1.1.1.1/limdim.ics?s=secret-token", provider: "booking") # IP literal: no DNS
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: users(:owner).api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path) = send(verb, path, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" })
  def body = response.parsed_body

  test "feeds by room, failing first, host only; Hôm nay counts the failing ones" do
    @feed.update_columns(last_error: "RuntimeError: HTTP 404", last_error_at: 1.hour.ago)
    as :staff, :get, calendar_feeds_api_v1_place_path(places(:tomo))
    assert_response :success
    assert_equal [ "Limdim", "Garden" ], body["rooms"].pluck("name")
    assert_equal [], body["rooms"].last["feeds"] # Chưa có kênh
    feeds = body["rooms"].first["feeds"].index_by { it["provider"] }
    assert_equal [ "Booking.com", "1.1.1.1", "gone", "Link iCal không còn dùng được. Lấy link mới trên Airbnb / Booking.com rồi thêm lại kênh." ],
      feeds["booking"].values_at("label", "host", "error", "error_message")
    assert_equal [ "www.airbnb.com", nil ], feeds["airbnb"].values_at("host", "error")
    assert_no_match(/secret-token|ical\/123/, response.body)

    as :staff, :get, today_api_v1_place_path(places(:tomo))
    assert_equal 1, body["feed_errors"]
  end

  test "Đồng bộ ngay: ok, then once a minute; staff too" do
    stub_request(:get, @feed.url).to_return(body: file_fixture("airbnb.ics").read)
    as :staff, :post, sync_api_v1_calendar_feed_path(@feed)
    assert_response :success
    assert_equal [ "2026-10-05T12:00:00.000+07:00", nil ], body.values_at("last_synced_at", "error")
    assert_equal "manual", @feed.sync_runs.sole.trigger
    assert_equal "booking", @feed.bookings.first.versions.last.whodunnit # logged as the OTA, whoever pressed

    travel 30.seconds
    as :owner, :post, sync_api_v1_calendar_feed_path(@feed)
    assert_response :too_many_requests
    assert_equal [ "rate_limited", "Vừa đồng bộ, thử lại sau 1 phút." ], body.values_at("error", "message")
    assert_requested :get, @feed.url, times: 1
  end

  test "Đồng bộ ngay that fails says why and changes nothing" do
    stub_request(:get, @feed.url).to_return(status: 500)
    as :owner, :post, sync_api_v1_calendar_feed_path(@feed)
    assert_response :unprocessable_entity
    assert_equal [ "sync_failed", "Đồng bộ lỗi. Không tải được lịch lúc này. hueni tự thử lại mỗi giờ.", "fetch" ],
      [ body["error"], body["message"], body.dig("feed", "error") ]
    assert_no_match(/secret-token/, response.body)
  end

  test "another owner's homestay and feed are 404" do
    other = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2).calendar_feeds.create!(url: "https://1.1.1.1/other.ics", provider: "agoda")
    as :owner, :post, sync_api_v1_calendar_feed_path(other)
    assert_response :not_found
    as :owner, :get, calendar_feeds_api_v1_place_path(places(:hiuhill))
    assert_response :not_found
    assert_not_requested :get, other.url
  end
end
