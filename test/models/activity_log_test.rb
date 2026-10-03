require "test_helper"

class ActivityLogTest < ActiveSupport::TestCase
  setup { travel_to Time.zone.local(2026, 10, 5, 12) }

  def as_owner(&) = PaperTrail.request(whodunnit: users(:owner).id.to_s, &)

  def assert_one_version(item, event)
    assert_difference -> { PaperTrail::Version.count }, 1 do
      yield
    end
    version = PaperTrail::Version.last
    assert_equal [ item.class.name, item.id, event ], [ version.item_type, version.item_id, version.event ]
    version
  end

  test "room create and settings changes are versioned with place and room" do
    room = nil
    assert_difference(-> { PaperTrail::Version.count }, 1) do
      as_owner { room = places(:tomo).rooms.create!(name: "Mây", max_guests: 2) }
    end
    version = PaperTrail::Version.last
    assert_equal [ "Room", "create", users(:owner).id.to_s, places(:tomo).id, room.id ],
      [ version.item_type, version.event, version.whodunnit, version.place_id, version.room_id ]

    version = assert_one_version(rooms(:garden), "update") { as_owner { rooms(:garden).update!(price: 350_000, max_guests: 3) } }
    assert_equal({ "price" => [ nil, 350_000 ], "max_guests" => [ 2, 3 ] }, version.object_changes)
    assert_equal [ places(:tomo).id, rooms(:garden).id ], [ version.place_id, version.room_id ]
  end

  test "becoming dirty is not logged, becoming clean is" do
    assert_no_difference(-> { PaperTrail::Version.count }) { rooms(:garden).dirty! }
    version = assert_one_version(rooms(:garden), "update") { rooms(:garden).clean! }
    assert_equal({ "housekeeping" => [ "dirty", "clean" ] }, version.object_changes)
  end

  test "booking create, edit and cancel are versioned; bookkeeping columns are not" do
    booking = nil
    assert_difference(-> { PaperTrail::Version.count }, 1) do
      as_owner { booking = rooms(:garden).bookings.create!(start_date: "2026-10-06", end_date: "2026-10-08", status: "hold", guest_name: "Chị Mai") }
    end
    version = PaperTrail::Version.last
    assert_equal [ "create", places(:tomo).id, rooms(:garden).id, users(:owner).id.to_s ],
      [ version.event, version.place_id, version.room_id, version.whodunnit ]
    assert_equal [ nil, "Chị Mai" ], version.object_changes["guest_name"]
    assert_not version.object_changes.key?("uid")

    version = assert_one_version(booking, "update") { booking.update!(note: "Đến muộn", end_date: "2026-10-09") }
    assert_equal({ "note" => [ nil, "Đến muộn" ], "end_date" => [ "2026-10-08", "2026-10-09" ] }, version.object_changes)

    version = assert_one_version(booking, "update") { booking.update!(status: "cancelled") }
    assert_equal [ "hold", "cancelled" ], version.object_changes["status"]

    assert_no_difference(-> { PaperTrail::Version.count }) { booking.touch }
  end

  test "check-in and check-out each log one version; the room turning dirty logs none" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07", status: "hold", guest_name: "Chị Mai")

    version = assert_one_version(booking, "update") { assert booking.check_in }
    assert_equal [ "hold", "confirmed" ], version.object_changes["status"]
    assert version.object_changes["checked_in_at"]

    version = assert_one_version(booking, "update") { assert booking.check_out }
    assert_equal [ "checked_out_at" ], version.object_changes.keys
    assert rooms(:garden).reload.dirty?
  end

  test "feed add and delete are versioned without the URL" do
    url = "https://1.1.1.1/calendar/ical/42.ics?s=secret-token"
    feed = nil
    assert_difference(-> { PaperTrail::Version.count }, 1) do
      feed = rooms(:garden).calendar_feeds.create!(url:, provider: "booking")
    end
    created = PaperTrail::Version.last
    assert_equal [ "CalendarFeed", "create", places(:tomo).id, rooms(:garden).id ],
      [ created.item_type, created.event, created.place_id, created.room_id ]
    assert_equal "booking", created.object_changes["provider"].last

    destroyed = assert_one_version(feed, "destroy") { feed.destroy! }
    assert_equal "booking", destroyed.object["provider"]

    [ created, destroyed ].each do |version|
      json = version.attributes.to_json
      assert_not_includes json, "secret-token"
      assert_not_includes json, "1.1.1.1"
    end
  end
end
