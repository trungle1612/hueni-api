module Admin::ActivityHelper
  # kind => [icon, round badge classes]. Full class names so Tailwind picks them up.
  ACTIVITY_KINDS = {
    check_in: [ "key", "bg-info/15 text-info" ],
    check_out: [ "log-out", "bg-secondary/15 text-secondary" ],
    clean: [ "sparkles", "bg-success/15 text-success" ],
    booking: [ "calendar", "bg-primary/15 text-primary" ],
    cancel: [ "x", "bg-base-300 text-base-content/70" ],
    edit: [ "pencil", "bg-base-300 text-base-content/70" ],
    sync: [ "refresh", "bg-accent/15 text-accent" ],
    room: [ "home", "bg-warning/15 text-warning" ],
    feed: [ "link", "bg-accent/15 text-accent" ],
    error: [ "alert", "bg-error/15 text-error" ],
    ok: [ "check", "bg-success/15 text-success" ]
  }.freeze

  # whodunnit => who: a user's name, an OTA ("airbnb" → "Airbnb"), or "Hệ thống" (console, seeds, unknown).
  def activity_names(versions)
    whodunnits = versions.map(&:whodunnit).uniq
    users = User.where(id: whodunnits.grep(/\A\d+\z/)).to_h { [ it.id.to_s, it.name ] }
    whodunnits.to_h { [ it, users[it] || CalendarFeed::PROVIDER_LABELS[it] || "Hệ thống" ] }
  end

  def activity_room_names(versions) = Room.where(id: versions.map(&:room_id).uniq).to_h { [ it.id, it.name ] }

  def activity_day(date)
    if date == Date.current then "Hôm nay"
    elsif date == Date.yesterday then "Hôm qua"
    else l(date, format: "%A %d/%m").upcase_first
    end
  end

  # { kind:, action:, detail: } for one change, e.g. { kind: :check_in, action: "Nhận phòng", detail: "Chị Mai" }.
  def activity_entry(version)
    changes = version.object_changes.to_h
    after = activity_after(version)
    kind, action, detail =
      case [ version.item_type, version.event ]
      in [ "Booking", "create" ]
        [ activity_ota?(version) ? :sync : :booking, after["status"] == "hold" ? "Giữ chỗ" : "Đặt phòng", activity_stay(after) ]
      in [ "Booking", "destroy" ] then [ activity_ota?(version) ? :sync : :cancel, "Xoá đặt phòng", activity_stay(after) ]
      in [ "Booking", "update" ] then activity_booking_update(version, changes, after)
      in [ "Room", "create" ] then [ :room, "Thêm phòng" ]
      in [ "Room", "update" ] then activity_room_update(changes)
      in [ "CalendarFeed", "create" | "destroy" ]
        [ :feed, version.event == "create" ? "Thêm kênh" : "Xoá kênh", CalendarFeed::PROVIDER_LABELS.fetch(after["provider"], "iCal") ]
      in [ "CalendarFeed", "update" ] then after["last_error"].present? ? [ :error, "Đồng bộ lỗi", after["last_error"] ] : [ :ok, "Đồng bộ lại được" ]
      else [ :edit, "Thay đổi" ]
      end
    { kind:, action:, detail: detail.presence }
  end

  def activity_icon(kind)
    icon, classes = ACTIVITY_KINDS.fetch(kind)
    tag.div(render("shared/icon", name: icon), class: "size-9 rounded-full flex items-center justify-center #{classes}")
  end

  private
    # The record as it was right after this change (before it, for a destroy).
    def activity_after(version)
      return version.object.to_h if version.event == "destroy"
      version.object.to_h.merge(version.object_changes.to_h.transform_values(&:last))
    end

    def activity_dates(attrs) = [ attrs["start_date"], attrs["end_date"] ].map { Date.parse(it).strftime("%d/%m") }.join("–")
    def activity_stay(attrs) = [ attrs["guest_name"].presence, activity_dates(attrs) ].compact.join(" ")
    def activity_value(value) = value.presence || "—"
    def activity_ota?(version) = CalendarFeed::PROVIDER_LABELS.key?(version.whodunnit)
    # The guest's name, or the stay's dates when there is none, so a check-in says which stay it was.
    def activity_guest(attrs) = attrs["guest_name"].presence || "Khách #{activity_dates(attrs)}"

    def activity_booking_update(version, changes, after)
      before = version.object.to_h
      if changes.key?("checked_in_at") then [ :check_in, "Nhận phòng", activity_guest(after) ]
      elsif changes.key?("checked_out_at") then [ :check_out, "Trả phòng", activity_guest(after) ]
      elsif changes["status"]&.last == "cancelled" then [ :cancel, "Huỷ", activity_stay(after) ]
      elsif changes.key?("status") then [ :booking, after["status"] == "hold" ? "Giữ chỗ" : "Xác nhận", activity_stay(after) ]
      elsif activity_ota?(version) then [ :sync, "Đổi ngày", "#{activity_dates(before)} → #{activity_dates(after)}" ]
      else [ :edit, "Sửa đặt phòng", activity_booking_changes(changes, before, after) ]
      end
    end

    def activity_booking_changes(changes, before, after)
      parts = []
      parts << "đổi ngày #{activity_dates(before)} → #{activity_dates(after)}" if changes.key?("start_date") || changes.key?("end_date")
      { "guest_name" => "khách", "guest_phone" => "SĐT", "guests" => "số khách" }.each do |attr, label|
        parts << "#{label}: #{activity_value(changes[attr][0])} → #{activity_value(changes[attr][1])}" if changes.key?(attr)
      end
      parts << "sửa ghi chú" if changes.key?("note")
      guest = after["guest_name"].presence unless changes.key?("guest_name")
      [ guest, parts.join(", ") ].compact.join(": ")
    end

    def activity_room_update(changes)
      return [ :clean, "Dọn xong" ] if changes.keys == [ "housekeeping" ]
      return [ :room, changes["active"][1] ? "Bật phòng" : "Tắt phòng" ] if changes.keys == [ "active" ]
      parts = []
      parts << "đổi tên #{changes["name"][0]} → #{changes["name"][1]}" if changes.key?("name")
      parts << "giá #{vnd(changes["price"][0]) || "chưa có"} → #{vnd(changes["price"][1]) || "chưa có"}" if changes.key?("price")
      parts << "tối đa #{changes["max_guests"][0]} → #{changes["max_guests"][1]} khách" if changes.key?("max_guests")
      parts << (changes["active"][1] ? "bật phòng" : "tắt phòng") if changes.key?("active")
      parts << "dọn xong" if changes.key?("housekeeping")
      [ :room, "Sửa phòng", parts.join(", ") ]
    end
end
