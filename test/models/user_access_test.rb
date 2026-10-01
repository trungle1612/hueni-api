require "test_helper"

# users(:owner) is a member of tomo (rooms limdim + garden, feed limdim_airbnb, booking limdim_confirmed).
class UserAccessTest < ActiveSupport::TestCase
  setup do
    @owner_b = User.create!(email_address: "b@example.com", name: "Anh Bình", password: "password123")
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
    loner = User.create!(email_address: "c@example.com", name: "Chú Cường", password: "password123")
    assert_empty loner.accessible_places
    assert_empty loner.accessible_rooms
    assert_empty loner.accessible_calendar_feeds
    assert_empty loner.accessible_bookings
  end

  test "admin sees everything once, even with memberships" do
    admin = users(:admin)
    admin.places << places(:tomo)
    assert_equal Place.order(:id).to_a, admin.accessible_places.order(:id).to_a
    assert_equal Room.count, admin.accessible_rooms.count
    assert_equal CalendarFeed.count, admin.accessible_calendar_feeds.count
    assert_equal Booking.count, admin.accessible_bookings.count
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
    owner.place_memberships.destroy_all
    assert_not owner.accessible_places.exists?(places(:tomo).id)
    assert_empty owner.accessible_rooms
  end
end
