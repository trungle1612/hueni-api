require "test_helper"

class Admin::SyncRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 5, 15, 30)
    @feed = calendar_feeds(:limdim_airbnb)
    @hiuhill_feed = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2)
      .calendar_feeds.create!(url: "https://1.1.1.1/hiu.ics", provider: "booking")
    @hiuhill_feed.sync_runs.create!(trigger: "manual", ok: false, error: "RuntimeError: HTTP 404",
      started_at: Time.zone.local(2026, 10, 5, 14, 12), finished_at: Time.zone.local(2026, 10, 5, 14, 12, 1))
    @feed.sync_runs.create!(trigger: "hourly", ok: true, created_count: 2, removed_count: 1,
      started_at: Time.zone.local(2026, 10, 5, 15, 0, 1), finished_at: Time.zone.local(2026, 10, 5, 15, 0, 2.5))
    @feed.bookings.create!(room: @feed.room, uid: "u1", start_date: "2026-10-06", end_date: "2026-10-08", source: "ical", guest_name: "Khách bí mật")
  end

  test "admins see every homestay's runs, newest first, grouped by hour" do
    log_in users(:admin)
    get admin_sync_runs_path

    assert_response :success
    assert_select "h1", "Lịch sử đồng bộ"
    assert_equal [ "Hôm nay · 15:00", "Hôm nay · 14:00" ], css_select("h3").map { it.text.squish }
    rows = css_select("[id^=sync_run_]").map { it.text.squish }
    assert_equal [
      "tomo homestay · Airbnb · Phòng Limdim +2 mới · 1 xoá 15:00:01 1,5 s",
      "Hiu Hill Homestay · Booking.com · Phòng Đồi Đồng bộ ngay RuntimeError: HTTP 404 14:12:00 1,0 s"
    ], rows
    assert_no_match "secret-token", response.body
    assert_no_match "Khách bí mật", response.body
    assert_select "aside a.menu-active", text: /Đồng bộ/
  end

  test "filters by homestay and failures" do
    log_in users(:admin)

    get admin_sync_runs_path(place: "tomo-homestay")
    assert_select "[id^=sync_run_]", 1
    assert_select "[id^=sync_run_]", text: /Limdim/

    get admin_sync_runs_path(failed: "1")
    assert_select "[id^=sync_run_]", 1
    assert_select "[id^=sync_run_]", text: /HTTP 404/
  end

  test "pages back by id" do
    55.times { @feed.sync_runs.create!(trigger: "hourly", ok: true, started_at: 2.days.ago, finished_at: 2.days.ago) }
    log_in users(:admin)

    get admin_sync_runs_path
    assert_select "[id^=sync_run_]", Admin::SyncRunsController::PER_PAGE
    older = css_select("a").find { it.text == "Xem cũ hơn" }["href"]

    get older
    assert_select "[id^=sync_run_]", 7
    assert_select "a", text: "Xem cũ hơn", count: 0
  end

  test "owners and staff get 404 and no menu item" do
    log_in users(:owner)
    get admin_sync_runs_path
    assert_response :not_found

    get admin_root_path
    assert_select "aside a", text: /Đồng bộ/, count: 0
  end
end
