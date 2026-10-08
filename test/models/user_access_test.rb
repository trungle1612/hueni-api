require "test_helper"

# users(:owner) is a member of tomo (rooms limdim + garden, feed limdim_airbnb, booking limdim_confirmed).
class UserAccessTest < ActiveSupport::TestCase
  setup do
    @owner_b = User.create!(phone_number: "0987000001", name: "Anh Bình", password: "password123")
    @owner_b.places << places(:hiuhill)
    @b_room = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    @b_feed = CalendarFeed.create!(room: @b_room, url: "https://1.1.1.1/b.ics", provider: "booking")
    @b_booking = Booking.create!(room: @b_room, start_date: "2026-10-10", end_date: "2026-10-12")
  end

  test "owner sees only their places, rooms, feeds and bookings" do
    owner = users(:owner)
    assert_equal [ places(:tomo) ], owner.accessible_places.to_a
    assert_equal rooms(:limdim, :garden).sort_by(&:id), owner.accessible_rooms.order(:id).to_a
    assert_equal [ calendar_feeds(:limdim_airbnb) ], owner.accessible_calendar_feeds.to_a
    assert_equal [ bookings(:limdim_confirmed) ], owner.accessible_bookings.to_a
  end

  test "finding another owner's records raises not found" do
    owner = users(:owner)
    assert_raises(ActiveRecord::RecordNotFound) { owner.accessible_places.find(places(:hiuhill).id) }
    assert_raises(ActiveRecord::RecordNotFound) { owner.accessible_rooms.find(@b_room.id) }
    assert_raises(ActiveRecord::RecordNotFound) { owner.accessible_calendar_feeds.find(@b_feed.id) }
    assert_raises(ActiveRecord::RecordNotFound) { owner.accessible_bookings.find(@b_booking.id) }
  end

  test "two owners sharing a place both see it" do
    @owner_b.places << places(:tomo)
    assert_includes @owner_b.accessible_places, places(:tomo)
    assert_includes users(:owner).accessible_places, places(:tomo)
  end

  test "owner without memberships sees nothing" do
    loner = User.create!(phone_number: "0987000002", name: "Chú Cường", password: "password123")
    assert_empty loner.accessible_places
    assert_empty loner.accessible_rooms
    assert_empty loner.accessible_calendar_feeds
    assert_empty loner.accessible_bookings
  end

  test "admins see homestay data only through a membership, like everyone else" do
    admin = users(:admin)
    assert_empty admin.accessible_places
    assert_empty admin.accessible_rooms
    assert_empty admin.accessible_calendar_feeds
    assert_empty admin.accessible_bookings

    admin.places << places(:tomo)
    assert_equal [ places(:tomo) ], admin.accessible_places.to_a
    assert_equal places(:tomo).rooms.count, admin.accessible_rooms.count
    assert_raises(ActiveRecord::RecordNotFound) { admin.accessible_places.find(places(:hiuhill).id) }
  end

  test "inactive rooms stay accessible to the owner" do
    rooms(:garden).update!(active: false)
    assert_includes users(:owner).accessible_rooms, rooms(:garden)
  end

  test "ical bookings of the owner's rooms are accessible" do
    ical = Booking.create!(room: rooms(:limdim), start_date: "2026-11-01", end_date: "2026-11-03",
      source: "ical", calendar_feed: calendar_feeds(:limdim_airbnb), uid: "x@airbnb.com")
    assert_includes users(:owner).accessible_bookings, ical
  end

  test "removing a membership removes access immediately" do
    owner = users(:owner)
    assert owner.accessible_places.exists?(places(:tomo).id)
    owner.place_memberships.delete_all # skips the last-owner rule (tested in PlaceMembershipTest)
    assert_not owner.accessible_places.exists?(places(:tomo).id)
    assert_empty owner.accessible_rooms
  end
end
