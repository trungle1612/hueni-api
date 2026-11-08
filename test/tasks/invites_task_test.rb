require "test_helper"
require "rake"

# invites:demo (#211): a made-up homestay for Zalo review, created once; each run prints a new owner code.
class InvitesTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    @task = Rake::Task["invites:demo"]
  end

  def run_demo(*args)
    @task.reenable
    capture_io { @task.invoke(*args) }.first
  end

  test "creates Homestay Demo with rooms and bookings once, and an owner code on every run" do
    output = run_demo
    place = Place.find_by!(slug: "demo-hueni")
    invite = place.invites.sole
    assert_includes output, invite.display_code
    assert_equal [ "owner", 5 ], [ invite.role, invite.max_uses ]
    assert_equal 4, place.rooms.count
    bookings = Booking.where(room: place.rooms)
    assert_equal 4, bookings.count
    assert bookings.all?(&:valid?)

    assert_no_difference -> { Booking.count } do
      run_demo("2", "3")
    end
    assert_equal [ 5, 2 ], place.invites.order(:id).pluck(:max_uses)
  end
end
