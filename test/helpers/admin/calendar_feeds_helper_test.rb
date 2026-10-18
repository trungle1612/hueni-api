require "test_helper"

class Admin::CalendarFeedsHelperTest < ActionView::TestCase
  test "sync errors in words: dead link, not a calendar, anything else" do
    assert_match "Lấy link mới", sync_error_message("RuntimeError: HTTP 404")
    assert_match "không đọc được thành lịch iCal", sync_error_message("RuntimeError: not an iCalendar feed")
    assert_match "tự thử lại mỗi giờ", sync_error_message("Net::OpenTimeout: execution expired")
  end
end
