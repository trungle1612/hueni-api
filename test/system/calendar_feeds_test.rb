require "application_system_test_case"

class CalendarFeedsTest < ApplicationSystemTestCase
  URL = "https://1.1.1.1/calendar/ical/42.ics?s=secret-token"

  setup do
    travel_to Time.zone.local(2026, 10, 5, 12)
    stub_request(:get, URL).to_return(body: file_fixture("airbnb.ics").read)
    visit new_session_path
    fill_in "Email", with: "lan@example.com"
    fill_in "Mật khẩu", with: "password123"
    click_button "Đăng nhập"
    assert_selector "h1", text: "Tổng quan"
  end

  test "owner adds a feed from the OTA overview, sees it synced, then deletes it" do
    click_on "Kênh OTA", match: :first
    find("[data-room='#{rooms(:garden).id}']").click
    select "Airbnb", from: "Kênh"
    fill_in "Link iCal", with: URL
    click_button "Thêm và đồng bộ"

    assert_text "Đã thêm và đồng bộ."
    feed = rooms(:garden).calendar_feeds.sole
    within("#calendar_feed_#{feed.id}") { assert_text "Đã đồng bộ" }
    assert_equal 2, feed.bookings.count

    within("#calendar_feed_#{feed.id}") { accept_confirm { click_button "Xoá" } }
    assert_text "Đã xoá kênh Airbnb."
    assert_not CalendarFeed.exists?(feed.id)
    assert_equal 0, rooms(:garden).bookings.count
  end
end
