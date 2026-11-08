require "test_helper"

class AnnouncementTest < ActiveSupport::TestCase
  test "content lines become blocks: ## heading, - bullets, 1. steps" do
    announcement = Announcement.new(content: "Mở đầu lạc\n## Có gì mới\n- Một\n-  Hai\n\n## Cách dùng\n1. Mở\n2. Bấm")
    assert_equal [ { h: nil, ordered: false, items: [ "Mở đầu lạc" ] },
                   { h: "Có gì mới", ordered: false, items: [ "Một", "Hai" ] },
                   { h: "Cách dùng", ordered: true, items: [ "Mở", "Bấm" ] } ], announcement.blocks
  end

  test "a button needs a Mini App path" do
    announcement = Announcement.new(title: "T", summary: "S", published_at: Time.current, cta: "Thử")
    assert_not announcement.valid?
    announcement.cta_path = "javascript:alert(1)"
    assert_not announcement.valid?
    announcement.cta_path = "/bookings/new"
    assert announcement.valid?
  end
end
