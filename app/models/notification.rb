# Thông báo (#213, #216): one member's inbox at one homestay, newest first. Events are worded as they happen, one row
# per homestay event, by the models where they happen (Booking, Payment, ShiftClose, Room, RefundRequest call the
# writers below) and saved by NotificationJob once the event commits, so a refused action leaves none. Today's OTA conflicts and undeclared
# guests (Today), failing feeds and hueni's announcements are current state, computed on read. Per user, only read
# marks (NotificationRead) and the types turned off (users.notifications_off) are stored.
class Notification < ApplicationRecord
  DAYS = 30
  # Cài đặt thông báo. channel = Trùng phòng và lỗi kênh, always on.
  TYPES = %w[book money reg room approve news channel].freeze
  OPTIONAL = (TYPES - %w[channel]).freeze
  # Khai báo lưu trú reminders, while guests are undeclared.
  REMINDER_HOURS = [ 8, 21 ].freeze

  # type: the setting it belongs to; icon: book | money | alert | room | team | news; tone: "" | err | warn | pos | info;
  # link: the Mini App screen to open ({ screen:, id: }), nil for none.
  Item = Data.define(:key, :type, :icon, :tone, :title, :body, :source, :at, :urgent, :unread, :link, :announcement) do
    def initialize(unread: true, link: nil, announcement: nil, **) = super
  end

  # Saved events by kind → [type, icon, tone, title, link screen].
  KINDS = {
    "booking" => [ "book", "book", "", "Đặt phòng mới", "booking" ],
    "cancel" => [ "book", "book", "", "Đặt phòng bị huỷ", "booking" ],
    "ota_delete" => [ "book", "book", "", "Đặt phòng bị huỷ", nil ],
    "ota_removed" => [ "channel", "alert", "warn", "OTA đã huỷ, khách đang ở", "booking" ],
    "payment" => [ "money", "money", "pos", "Thu tiền", "booking" ],
    "shift" => [ "money", "money", "warn", "Chốt ca lệch", "shift" ],
    "clean" => [ "room", "room", "", "Dọn xong", "housekeeping" ],
    "damage" => [ "room", "room", "warn", "Báo hỏng / thiếu đồ", "housekeeping" ],
    "refund_request" => [ "approve", "team", "warn", "Yêu cầu hoàn tiền chờ bạn duyệt", "approvals" ]
  }.freeze
  OWNER_ONLY = %w[payment shift refund_request].freeze

  belongs_to :place

  # Worded now, saved by NotificationJob after the event commits; created_at is when it happened.
  # Who did it: the signed-in user, else by: (the OTA, the guest on the booking page), else "Hệ thống" (jobs, console).
  def self.record(kind, place:, details: [], room: nil, booking: nil, refund_request: nil, by: nil)
    user = Current.user unless by
    NotificationJob.perform_later(place_id: place.id, kind:, title: KINDS.fetch(kind)[3], actor_id: user&.id, source: by || user&.name || "Hệ thống",
      body: [ *details, ("Phòng #{room.name}" if room) ].compact_blank.join(" · ").presence,
      booking_id: booking&.id, room_id: room&.id, refund_request_id: refund_request&.id, created_at: Time.current)
  end

  # Đặt phòng mới / bị huỷ / OTA đã huỷ: an iCal booking is the OTA's doing, an online one the guest's.
  def self.booking(kind, booking, *details)
    by = booking.calendar_feed&.provider_label || "iCal" if booking.ical?
    by ||= "Khách đặt online" if booking.online && !Current.user
    record(kind, place: booking.room.place, room: booking.room, booking: (booking unless booking.destroyed?), by:,
      details: details.presence || [ [ booking.guest_name.presence, dates(booking) ].compact.join(" ") ])
  end

  def self.payment(payment)
    booking = payment.booking
    record("payment", place: booking.room.place, room: booking.room, booking:,
      details: [ VndPrice.format(payment.amount), Payment::METHODS[payment.payment_method], booking.code ])
  end

  def self.refund_request(request)
    booking = request.booking
    record("refund_request", place: booking.room.place, room: booking.room, booking:, refund_request: request,
      details: [ VndPrice.format(request.amount), Payment::METHODS[request.payment_method], booking.code ])
  end

  def self.shift(close)
    record("shift", place: close.place, details: [ "#{close.difference.negative? ? "Thiếu" : "Thừa"} #{VndPrice.format(close.difference.abs)}", close.note ])
  end

  def self.room(kind, room, *details) = record(kind, place: room.place, room:, details:)

  def self.dates(booking) = [ booking.start_date, booking.end_date ].map { it.strftime("%d/%m") }.join("–")

  def self.prune = where(created_at: ...(DAYS + 1).days.ago).delete_all

  def self.for(user, place)
    items = saved(user, place) + today(place) + feeds(place) + Announcement.shown.map { announcement(it) }
    off = user.notifications_off & OPTIONAL
    items = items.reject { it.type.in?(off) }.sort_by(&:at).reverse
    read = user.notification_reads.where(key: items.map(&:key)).pluck(:key).to_set
    items.map { it.with(unread: !read.include?(it.key)) }
  end

  # What others did here in the last DAYS days; money and approvals for owners only.
  def self.saved(user, place)
    kinds = KINDS.keys
    kinds -= OWNER_ONLY unless user.allowed_to?(:manage, place)
    rows = where(place:, kind: kinds, created_at: DAYS.days.ago..).where("actor_id IS NULL OR actor_id <> ?", user.id).to_a
    pending = RefundRequest.pending.where(id: rows.filter_map(&:refund_request_id)).ids.to_set
    rows.map do |row|
      type, icon, tone, _, screen = KINDS.fetch(row.kind)
      Item.new(key: "n#{row.id}", type:, icon:, tone:, title: row.title, body: row.body, source: row.source, at: row.created_at,
        urgent: pending.include?(row.refund_request_id), link: screen && { screen:, id: (row.booking_id if screen == "booking") })
    end
  end

  # Cần xử lý from Hôm nay: OTA conflicts (gone once resolved) and one reminder per REMINDER_HOURS for undeclared guests.
  def self.today(place)
    today = Today.new(place.rooms)
    start = Time.current.beginning_of_day
    conflicts = today.issues.select { it.kind == :error }.map do |issue|
      Item.new(key: "c#{issue.booking.id}-#{issue.date.iso8601}", type: "channel", icon: "alert", tone: "err", title: issue.title,
        body: issue.detail, source: "Kênh OTA", at: start, urgent: true, link: { screen: "booking", id: issue.booking.id })
    end
    undeclared = today.issues.select { it.kind == :stay }
    # Keyed by homestay: a read reminder at one homestay must not mark another's.
    reminders = REMINDER_HOURS.map { start.change(hour: it) }.select { undeclared.any? && it <= Time.current }.map do |at|
      Item.new(key: "r#{place.id}-#{at.strftime("%Y%m%d%H")}", type: "reg", icon: "alert", tone: "warn", title: "#{undeclared.size} đặt phòng chưa khai báo lưu trú",
        body: undeclared.map(&:detail).first(3).join("; "), source: "Khai báo lưu trú", at:, urgent: true, link: { screen: "today" })
    end
    conflicts + reminders
  end

  # A feed failing now; failing again after a recovery is a new notification.
  def self.feeds(place)
    CalendarFeed.joins(:room).where(rooms: { place_id: place.id }).where.not(last_error_at: nil).includes(:room).map do |feed|
      Item.new(key: "f#{feed.id}-#{feed.last_error_at.to_i}", type: "channel", icon: "alert", tone: "err", title: "#{feed.provider_label} không đồng bộ được",
        body: "Phòng #{feed.room.name} · #{feed.error_message}", source: "Kênh OTA", at: feed.last_error_at, urgent: true, link: { screen: "channels" })
    end
  end

  def self.announcement(announcement)
    Item.new(key: "a#{announcement.id}", type: "news", icon: "news", tone: announcement.kind == "feature" ? "info" : "", title: announcement.title,
      body: announcement.summary, source: "hueni", at: announcement.published_at, urgent: false, link: nil, announcement: announcement.detail)
  end
  private_class_method :record, :saved, :today, :feeds, :announcement
end
