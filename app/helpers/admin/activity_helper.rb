module Admin::ActivityHelper
  BOOKING_STATUS_WORDS = { "hold" => "giữ chỗ", "confirmed" => "xác nhận", "cancelled" => "huỷ" }.freeze

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

  def activity_error?(version) = version.item_type == "CalendarFeed" && version.event == "update" && activity_after(version)["last_error"].present?

  def activity_text(version)
    changes = version.object_changes.to_h
    after = activity_after(version)
    case [ version.item_type, version.event ]
    in [ "Booking", "create" ] then "#{after["status"] == "hold" ? "giữ chỗ" : "thêm đặt phòng"} #{activity_stay(after)}"
    in [ "Booking", "destroy" ] then "xoá đặt phòng #{activity_stay(after)}"
    in [ "Booking", "update" ] then activity_booking_changes(changes, version.object.to_h, after)
    in [ "Room", "create" ] then "thêm phòng"
    in [ "Room", "update" ] then activity_room_changes(changes)
    in [ "CalendarFeed", "create" | "destroy" ] then "#{version.event == "create" ? "thêm" : "xoá"} kênh #{CalendarFeed::PROVIDER_LABELS.fetch(after["provider"], "iCal")}"
    in [ "CalendarFeed", "update" ] then after["last_error"].present? ? "đồng bộ lỗi: #{after["last_error"]}" : "đồng bộ lại được"
    else "thay đổi"
    end
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

    def activity_booking_changes(changes, before, after)
      guest = after["guest_name"].presence
      parts = []
      if changes.key?("checked_in_at") then parts << [ "nhận phòng", guest ].compact.join(" ")
      elsif changes.key?("status") then parts << "#{BOOKING_STATUS_WORDS.fetch(after["status"])} #{activity_stay(after)}"
      end
      parts << [ "trả phòng", guest ].compact.join(" ") if changes.key?("checked_out_at")
      parts << "đổi ngày #{activity_dates(before)} → #{activity_dates(after)}" if changes.key?("start_date") || changes.key?("end_date")
      { "guest_name" => "khách", "guest_phone" => "SĐT", "guests" => "số khách" }.each do |attr, label|
        parts << "#{label}: #{activity_value(changes[attr][0])} → #{activity_value(changes[attr][1])}" if changes.key?(attr)
      end
      parts << "sửa ghi chú" if changes.key?("note")
      parts.join(", ")
    end

    def activity_room_changes(changes)
      parts = []
      parts << "đổi tên #{changes["name"][0]} → #{changes["name"][1]}" if changes.key?("name")
      parts << "giá #{vnd(changes["price"][0]) || "chưa có"} → #{vnd(changes["price"][1]) || "chưa có"}" if changes.key?("price")
      parts << "tối đa #{changes["max_guests"][0]} → #{changes["max_guests"][1]} khách" if changes.key?("max_guests")
      parts << (changes["active"][1] ? "bật phòng" : "tắt phòng") if changes.key?("active")
      parts << "dọn xong" if changes.key?("housekeeping")
      parts.join(", ")
    end
end
