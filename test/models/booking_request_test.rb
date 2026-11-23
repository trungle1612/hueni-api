require "test_helper"

# Hiển thị trên hue-ni (#282): approve mode requests, their deadline, Nhận / Từ chối, the hue-ni-only hold and the checklist.
class BookingRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    travel_to Time.zone.local(2026, 10, 1, 12) # limdim booked 01–03/10 by Anh Minh
    rooms(:garden).update!(room_type: "double", price: 400_000)
    rooms(:limdim).update!(room_type: "double", price: 500_000)
    @place = places(:tomo)
    site_ready(@place)
    @place.update!(site_open: true)
  end

  def ask(**attrs) = @place.book_online(room_type: "double", start_date: "2026-10-01", end_date: "2026-10-02", guests: 2, guest_name: "Chị Hoa", guest_phone: "0905 111 333", **attrs)

  test "approve mode: a pending request with its deadline, no booking; past the deadline it expires and can't be answered" do
    assert_equal "approve", Place.new.site_mode
    request = ask
    assert_kind_of BookingRequest, request
    assert_equal [ "pending", Time.zone.local(2026, 10, 1, 12, 30), "double", "Chị Hoa" ], request.values_at(:status, :reply_by, :room_type, :guest_name)
    assert_match(/\AYC-\d{4}\z/, request.code)
    assert_equal 0, Booking.where(online: true).count

    travel 31.minutes
    assert_equal "expired", request.site_status
    assert_not request.accept(room: rooms(:garden), deposit_percent: 0)
    assert_equal [ BookingRequest::CLOSED ], request.errors[:base]
    BookingRequest.expire
    assert request.reload.expired?
    assert_equal 0, Booking.where(online: true).count
  end

  test "a pending request holds the last room on hue-ni only: not on the calendar or vacancy" do
    ask
    assert_equal [ Place::SITE_FULL ], ask(guest_name: "Anh Tú").errors[:base]
    @place.update!(site_mode: "auto")
    assert_equal [ Place::SITE_FULL ], ask(guest_name: "Anh Tú").errors[:base], "auto mode respects the hold too"
    assert_empty Booking.new(room: rooms(:garden), start_date: Date.current, end_date: Date.tomorrow).date_problems
    assert_equal 1, Vacancy.on(Date.current).dig(@place.slug, :left)

    assert ask(start_date: "2026-10-02", end_date: "2026-10-03", guest_name: "Anh Tú").persisted?, "the next night shares the room"
    travel 31.minutes
    assert ask(guest_name: "Anh Tú").persisted?, "an expired request holds nothing"
  end

  test "a picked room (#290) is held exactly; typed requests take the other rooms, never twice" do
    limdim, garden = rooms(:limdim).id, rooms(:garden).id
    stay = { start_date: "2026-10-05", end_date: "2026-10-06" }
    picked = ask(room_id: limdim, **stay)
    assert_equal [ rooms(:limdim), "double" ], [ picked.room, picked.room_type ]
    assert_equal [ Place::SITE_ROOM_FULL ], ask(room_id: limdim, guest_name: "Anh Tú", **stay).errors[:base]
    assert ask(guest_name: "Anh Tú", **stay).persisted?, "a typed request takes the room left"
    assert_equal [ Place::SITE_FULL ], ask(guest_name: "Chị Mai", **stay).errors[:base]
    assert_equal [ Place::SITE_ROOM_FULL ], ask(room_id: garden, guest_name: "Chị Mai", **stay).errors[:base]

    stay = { start_date: "2026-10-07", end_date: "2026-10-08" }
    assert ask(**stay).persisted?
    assert ask(room_id: garden, guest_name: "Anh Tú", **stay).persisted?, "the typed hold leaves the picked room alone"
    assert_equal [ Place::SITE_ROOM_FULL ], ask(room_id: limdim, guest_name: "Chị Mai", **stay).errors[:base]
    assert_empty @place.site_free_rooms(@place.rooms.order(:name).to_a, Date.new(2026, 10, 7), Date.new(2026, 10, 8))
    perform_enqueued_jobs
    assert_match "Phòng đôi · Phòng Garden · ", Notification.where(kind: "booking_request").last.body
  end

  test "holds by need (#290): Nhận leaves a picked room alone, a picked room taken or retyped still holds one, sizes count" do
    stay = { start_date: "2026-10-05", end_date: "2026-10-06" }
    typed = ask(**stay)
    picked = ask(room_id: rooms(:limdim).id, guest_name: "Anh Tú", **stay)
    assert_equal [ rooms(:garden) ], typed.free_rooms
    assert_not typed.accept(room: rooms(:limdim), deposit_percent: 0)
    assert_equal [ "Phòng Limdim đang giữ cho yêu cầu khác trên hue-ni" ], typed.errors[:base]
    assert typed.accept(room: rooms(:garden), deposit_percent: 0)

    picked.update!(start_date: "2026-10-07", end_date: "2026-10-08")
    rooms(:limdim).bookings.create!(start_date: "2026-10-07", end_date: "2026-10-08", guest_name: "Khách OTA")
    assert_equal [ Place::SITE_FULL ], ask(start_date: "2026-10-07", end_date: "2026-10-08").errors[:base], "its room taken, it holds Garden"
    picked.update!(start_date: "2026-10-09", end_date: "2026-10-10")
    rooms(:limdim).update!(room_type: "family")
    assert_equal [ Place::SITE_FULL ], ask(start_date: "2026-10-09", end_date: "2026-10-10").errors[:base], "its room retyped, it holds Garden"

    rooms(:limdim).update!(room_type: "double")
    stay = { start_date: "2026-10-11", end_date: "2026-10-12" }
    assert ask(guests: 4, **stay).persisted?
    assert_equal [ Place::SITE_ROOM_FULL ], ask(room_id: rooms(:limdim).id, guest_name: "Chị Mai", **stay).errors[:base], "Limdim is the only room for 4"
    assert ask(room_id: rooms(:garden).id, guest_name: "Chị Mai", **stay).persisted?
  end

  test "a picked room must be this homestay's, on, of a shown type, big enough and free; auto mode books it" do
    other = places(:hiuhill).rooms.create!(name: "Sen", room_type: "double", max_guests: 2)
    assert_equal [ "Phòng này không nhận đặt online" ], ask(room_id: other.id).errors[:base]
    assert_equal [ "Phòng này không nhận đặt online" ], ask(room_id: "abc").errors[:base]
    rooms(:garden).update!(active: false)
    assert_equal [ "Phòng này không nhận đặt online" ], ask(room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-06").errors[:base]
    rooms(:garden).update!(active: true, room_type: "family")
    @place.update!(site_hidden_room_types: [ "family" ])
    assert_equal [ "Phòng này không nhận đặt online" ], ask(room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-06").errors[:base]
    @place.update!(site_hidden_room_types: [])
    assert_equal [ "nhiều hơn sức chứa của phòng này" ], ask(room_id: rooms(:garden).id, guests: 3, start_date: "2026-10-05", end_date: "2026-10-06").errors[:guests]
    assert_equal [ Place::SITE_ROOM_FULL ], ask(room_id: rooms(:limdim).id).errors[:base], "Anh Minh is in limdim"
    assert_equal 0, BookingRequest.count

    @place.update!(site_mode: "auto", site_deposit_percent: 30)
    booking = ask(room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-06")
    assert_equal [ true, rooms(:garden), true ], [ booking.persisted?, booking.room, booking.held? ]
  end

  test "Nhận books the room, held for the deposit picked; a room taken meanwhile is refused with the reason" do
    request = ask
    assert request.accept(room: rooms(:garden), deposit_percent: "50")
    booking = request.booking
    assert_equal [ "accepted", 50 ], request.reload.values_at(:status, :deposit_percent)
    assert_equal [ rooms(:garden), true, "Chị Hoa", Time.zone.local(2026, 10, 1, 12, 30) ], booking.values_at(:room, :online, :guest_name, :hold_expires_at)
    assert_equal 200_000, booking.site_deposit(50)
    assert_not request.accept(room: rooms(:garden), deposit_percent: 0), "answered once"

    late = ask(start_date: "2026-10-05", end_date: "2026-10-06")
    rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06", guest_name: "Anh Tú")
    assert_no_difference -> { Booking.count } do
      assert_not late.accept(room: rooms(:garden), deposit_percent: 0)
    end
    assert late.errors[:base].any?
    assert late.reload.pending?
    assert_not late.accept(room: places(:hiuhill).rooms.create!(name: "101", max_guests: 2), deposit_percent: 0)
    assert_equal [ "Phòng không thuộc cơ sở này" ], late.errors[:base]
    assert_not late.accept(room: rooms(:limdim), deposit_percent: 40)
    rooms(:limdim).update!(room_type: "family")
    assert_not late.accept(room: rooms(:limdim), deposit_percent: 0)
    assert_equal [ "Phòng Limdim không phải Phòng đôi" ], late.errors[:base]
    rooms(:limdim).update!(room_type: "double", active: false)
    assert_not late.accept(room: rooms(:limdim), deposit_percent: 0)
    assert_equal [ "Phòng Limdim đang tắt" ], late.errors[:base]
  end

  test "Từ chối needs a reason; suggested dates are kept when they make sense" do
    request = ask
    assert_not request.decline(reason: nil)
    assert request.reload.pending?
    assert_not request.decline(reason: "full", suggested_start_date: "2026-10-05", suggested_end_date: "2026-10-05")
    assert request.decline(reason: "full", suggested_start_date: "2026-10-05", suggested_end_date: "2026-10-07")
    assert_equal [ "declined", "full", Date.new(2026, 10, 5) ], request.reload.values_at(:status, :decline_reason, :suggested_start_date)
    assert ask(guest_name: "Anh Tú").persisted?, "a declined request holds nothing"
  end

  test "a new request is saved for owner and staff and pushed at once, for as long as the reply deadline" do
    WebPush.key = OpenSSL::PKey::EC.generate("prime256v1")
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    @place.place_memberships.create!(user: staff, role: "staff")
    browser = OpenSSL::PKey::EC.generate("prime256v1")
    PushSubscription.save_for(staff.sessions.create!, endpoint: "https://fcm.googleapis.com/fcm/send/abc",
      p256dh: WebPush.encode(browser.public_key.to_bn.to_s(2)), auth: WebPush.encode(SecureRandom.random_bytes(16)))
    stub_request(:post, /fcm/).to_return(status: 201)

    perform_enqueued_jobs { ask }
    notification = Notification.sole
    assert_equal [ "booking_request", "Yêu cầu đặt phòng từ hue-ni", "Chị Hoa · Phòng đôi · 01/10–02/10", "Khách đặt online" ],
      notification.values_at(:kind, :title, :body, :source)
    assert_equal [ users(:owner), staff ].to_set, notification.recipients.to_set
    assert_requested :post, /fcm/, headers: { "Urgency" => "high", "TTL" => "1800" }
    assert Notification.for(users(:owner), @place).find { it.key == notification.key }.urgent, "Cần xử lý while it waits"

    travel 10.minutes
    assert_equal({ urgency: "high", ttl: 1200 }, notification.push_options, "only until reply_by")
    travel 21.minutes
    assert_nil notification.push_options
    perform_enqueued_jobs { PushNotificationJob.perform_later(notification) }
    assert_requested :post, /fcm/, times: 1
    assert_not Notification.for(users(:owner), @place).find { it.key == notification.key }.urgent
  ensure
    WebPush.key = nil
  end

  test "the checklist: photos for every shown type, the map pin, times and rules, the bank; turning on needs them all" do
    assert_empty @place.site_missing
    rooms(:garden).update!(room_type: "family")
    RoomPhoto.where(room: rooms(:garden)).delete_all
    @place.assign_attributes(lat: nil, check_in_time: nil)
    assert @place.valid?, "a page already open stays open"
    @place.bank_account = nil
    assert_equal %w[photos map rules bank], @place.site_missing

    @place.update!(site_open: false)
    assert_not @place.update(site_open: true)
    assert_equal Place::SITE_CHECKLIST.values.to_set, @place.errors[:site_open].to_set
    assert_not @place.update(check_in_time: "2pm")
  end
end
