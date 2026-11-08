# Thông báo (#213): one member's inbox at one homestay, built from what is already recorded, newest first:
# paper_trail versions of the last DAYS days that someone else did (worded by Activity), today's OTA conflicts and
# undeclared guests (Today), failing feeds and hueni's announcements. Only read marks (NotificationRead) and the
# types a user turned off (users.notifications_off) are stored.
class Notification
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

  # Versions that notify, by [item_type, Activity action] → [type, icon, tone, title (nil = Activity's), link screen].
  EVENTS = {
    [ "Booking", "Đặt phòng" ] => [ "book", "book", "", "Đặt phòng mới", "booking" ],
    [ "Booking", "Huỷ" ] => [ "book", "book", "", "Đặt phòng bị huỷ", "booking" ],
    [ "Booking", "Xoá đặt phòng" ] => [ "book", "book", "", "Đặt phòng bị huỷ", nil ],
    [ "Booking", "OTA đã huỷ, khách đang ở" ] => [ "channel", "alert", "warn", nil, "booking" ],
    [ "Payment", "Thu tiền" ] => [ "money", "money", "pos", nil, "booking" ],
    [ "ShiftClose", "Chốt ca lệch" ] => [ "money", "money", "warn", nil, "shift" ],
    [ "Room", "Dọn xong" ] => [ "room", "room", "", nil, "housekeeping" ],
    [ "Room", "Báo hỏng / thiếu đồ" ] => [ "room", "room", "warn", nil, "housekeeping" ],
    [ "RefundRequest", "Xin hoàn tiền" ] => [ "approve", "team", "warn", "Yêu cầu hoàn tiền chờ bạn duyệt", "approvals" ]
  }.freeze
  OWNER_ONLY = %w[Payment ShiftClose RefundRequest].freeze

  def self.for(user, place)
    items = versions(user, place) + today(place) + feeds(place) + Announcement.shown.map { announcement(it) }
    off = user.notifications_off & OPTIONAL
    items = items.reject { it.type.in?(off) }.sort_by(&:at).reverse
    read = user.notification_reads.where(key: items.map(&:key)).pluck(:key).to_set
    items.map { it.with(unread: !read.include?(it.key)) }
  end

  def self.versions(user, place)
    types = EVENTS.keys.map(&:first).uniq
    types -= OWNER_ONLY unless user.allowed_to?(:manage, place)
    # ponytail: words every version of the window in Ruby; prefilter in SQL if a homestay logs thousands a month.
    versions = PaperTrail::Version.where(place_id: place.id, item_type: types, created_at: DAYS.days.ago..)
      .where("whodunnit IS NULL OR whodunnit <> ?", user.id.to_s).order(:id).to_a
    pending = RefundRequest.pending.where(id: versions.select { it.item_type == "RefundRequest" }.map(&:item_id)).ids.to_set
    Activity.lines(versions).zip(versions).filter_map do |line, version|
      event = EVENTS[[ version.item_type, line.action ]] or next
      type, icon, tone, title, screen = event
      item_id = version.item_type == "Booking" ? version.item_id : version.object_changes.to_h.dig("booking_id", 1)
      Item.new(key: "v#{version.id}", type:, icon:, tone:, title: title || line.action,
        body: [ line.detail, ("Phòng #{line.room_name}" if line.room_name) ].compact.join(" · "), source: line.actor, at: line.at,
        urgent: version.item_type == "RefundRequest" && pending.include?(version.item_id), link: screen && { screen:, id: (item_id if screen == "booking") })
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
    reminders = REMINDER_HOURS.map { start.change(hour: it) }.select { undeclared.any? && it <= Time.current }.map do |at|
      Item.new(key: "r#{at.strftime("%Y%m%d%H")}", type: "reg", icon: "alert", tone: "warn", title: "#{undeclared.size} đặt phòng chưa khai báo lưu trú",
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
  private_class_method :versions, :today, :feeds, :announcement
end
