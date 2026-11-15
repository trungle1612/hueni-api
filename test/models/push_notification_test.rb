require "test_helper"

# Web Push (#237): a saved Thông báo goes to the phones of those who see it in their inbox; an expired one is deleted.
class PushNotificationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ENDPOINT = "https://fcm.googleapis.com/fcm/send/abc".freeze

  setup do
    travel_to Time.zone.local(2026, 11, 8, 14, 0)
    WebPush.key = OpenSSL::PKey::EC.generate("prime256v1")
    @browser = OpenSSL::PKey::EC.generate("prime256v1")
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
  end

  teardown { WebPush.key = nil }

  def subscribe(user, endpoint = ENDPOINT)
    PushSubscription.save_for(user.sessions.create!, endpoint:, p256dh: WebPush.encode(@browser.public_key.to_bn.to_s(2)),
      auth: WebPush.encode(SecureRandom.random_bytes(16)))
  end

  def notify(kind, by: nil) = Notification.send(:record, kind, place: places(:tomo), details: [ "Chị Hoa 08/11–10/11" ], room: rooms(:limdim), by:)

  test "endpoints only at the browsers' push services, keys of the right size" do
    assert subscribe(users(:owner)).persisted?
    assert subscribe(users(:owner), "https://web.push.apple.com/QK1").persisted?
    assert subscribe(users(:owner), "https://updates.push.services.mozilla.com/wpush/v2/x").persisted?
    [ "http://fcm.googleapis.com/x", "https://fcm.googleapis.com.evil.test/x", "https://169.254.169.254/x", "https://fcm.googleapis.com:8443/x", "nope" ].each do |endpoint|
      assert_not subscribe(users(:owner), endpoint).persisted?, endpoint
    end
    assert_not PushSubscription.save_for(users(:owner).sessions.create!, endpoint: ENDPOINT + "2", p256dh: "abc", auth: "abc").persisted?
  end

  test "a phone used by another login moves to it; logging out stops its pushes" do
    first = subscribe(users(:owner))
    subscribe(@staff)
    assert_equal [ @staff ], PushSubscription.where(id: first.id).map { it.session.user }
    @staff.sessions.destroy_all
    assert_empty PushSubscription.all
  end

  test "pushed to the members who see it: not the actor, money for owners, types turned off skipped" do
    owner, staff = subscribe(users(:owner)), subscribe(@staff, "https://web.push.apple.com/staff")
    requests = []
    stub_request(:post, /fcm|apple/).to_return { |request| requests << request; { status: 201 } }

    perform_enqueued_jobs { Current.set(session: @staff.sessions.first) { notify("booking") } }
    assert_equal [ "fcm.googleapis.com" ], requests.map { it.uri.host } # the owner's phone; Bé Na did it

    perform_enqueued_jobs { notify("payment") }
    assert_equal 2, requests.size # owners only
    assert_equal "fcm.googleapis.com", requests.last.uri.host

    @staff.update!(notifications_off: %w[book])
    users(:owner).update!(notifications_off: %w[book channel]) # channel can't be turned off
    perform_enqueued_jobs { notify("booking", by: "Airbnb") }
    perform_enqueued_jobs { notify("ota_removed", by: "Airbnb") }
    assert_equal 4, requests.size # Bé Na: nothing for book, both get channel

    request = requests.find { it.uri.host == "fcm.googleapis.com" && it.body.present? }
    assert_equal %w[aes128gcm 86400], request.headers.values_at("Content-Encoding", "Ttl")
    token, key = request.headers["Authorization"].match(/\Avapid t=(\S+), k=(\S+)\z/).captures
    assert_equal WebPush.public_key, key
    input, signature = token.rpartition(".").values_at(0, 2)
    r, s = WebPush.decode(signature).unpack("a32a32").map { OpenSSL::ASN1::Integer(OpenSSL::BN.new(it, 2)) }
    assert WebPush.key.verify("SHA256", OpenSSL::ASN1::Sequence([ r, s ]).to_der, input), "VAPID signed with our key"
    assert_equal "https://fcm.googleapis.com", JSON.parse(WebPush.decode(input.split(".").last))["aud"]
    assert [ owner, staff ].all?(&:persisted?)
  end

  test "the payload: the inbox's words, the homestay, quiet at night except channel problems" do
    perform_enqueued_jobs(only: NotificationJob) { notify("booking", by: "Airbnb") }
    notification = Notification.last
    payload = notification.push_payload(users(:owner))
    assert_equal({ title: "Đặt phòng mới · #{places(:tomo).name}", body: "Chị Hoa 08/11–10/11 · Phòng #{rooms(:limdim).name}", tag: "n#{notification.id}",
      silent: false, url: "/thong-bao/n#{notification.id}?co_so=#{places(:tomo).slug}" }, payload)

    travel_to Time.zone.local(2026, 11, 8, 22, 30)
    assert notification.push_payload(users(:owner))[:silent]
    users(:owner).quiet_hours = false
    assert_not notification.push_payload(users(:owner))[:silent]
    users(:owner).quiet_hours = true
    perform_enqueued_jobs(only: NotificationJob) { notify("ota_removed", by: "Airbnb") }
    assert_not Notification.last.push_payload(users(:owner))[:silent]
  end

  test "an expired subscription is deleted and the job does not fail; other errors are reported, the rest still sent" do
    subscribe(users(:owner))
    gone = "https://web.push.apple.com/gone"
    subscribe(users(:owner), gone)
    stub_request(:post, gone).to_return(status: 410)
    stub_request(:post, ENDPOINT).to_return(status: 500).then.to_return(status: 201)

    perform_enqueued_jobs { notify("booking", by: "Airbnb") }
    assert_equal [ ENDPOINT ], PushSubscription.pluck(:endpoint)
    perform_enqueued_jobs { notify("booking", by: "Airbnb") }
    assert_requested :post, ENDPOINT, times: 2
  end

  test "an announcement goes once, at its Hiện từ, to owners and staff with push on, unless news is off" do
    subscribe(users(:owner))
    subscribe(@staff, "https://web.push.apple.com/na")
    @staff.update!(notifications_off: %w[news])
    stub_request(:post, ENDPOINT).to_return(status: 201)
    announcement = Announcement.create!(kind: "maintenance", title: "Bảo trì 02:00", summary: "Tạm ngưng 30 phút", published_at: 2.hours.from_now)
    assert_enqueued_with(job: PushAnnouncementJob, args: [ announcement ], at: 2.hours.from_now)
    announcement.update!(published_at: 3.hours.from_now)

    travel 3.hours + 1.minute
    perform_enqueued_jobs
    assert_requested :post, ENDPOINT, times: 1
    assert_not_requested :post, "https://web.push.apple.com/na"
    assert_not_nil announcement.reload.pushed_at
    assert_equal({ title: "Bảo trì 02:00", body: "Tạm ngưng 30 phút", tag: "a#{announcement.id}", silent: false,
      url: "/thong-bao/a#{announcement.id}" }, announcement.push_payload(users(:owner)))
    assert_no_enqueued_jobs { announcement.update!(title: "Bảo trì 02:30", published_at: 1.hour.from_now) }
  end

  test "no key, no push" do
    WebPush.key = nil
    subscribe(users(:owner))
    assert_no_enqueued_jobs(only: PushNotificationJob) { perform_enqueued_jobs(only: NotificationJob) { notify("booking", by: "Airbnb") } }
    assert_no_enqueued_jobs { Announcement.create!(kind: "feature", title: "Báo cáo", summary: "Mới", published_at: Time.current) }
  end
end
