# The activity log (#46) in words: one paper_trail version → { kind:, action:, detail: } in Vietnamese, plus who did it
# and in which room. The admin's Hoạt động / Lịch sử (Admin::ActivityHelper) and the Mini App (#158) both read it.
class Activity
  # whodunnit => who: a user's name, an OTA ("airbnb" → "Airbnb"), or "Hệ thống" (console, seeds, unknown).
  def self.actors(versions)
    whodunnits = versions.map(&:whodunnit).uniq
    users = User.where(id: whodunnits.grep(/\A\d+\z/)).to_h { [ it.id.to_s, it.name ] }
    whodunnits.to_h { [ it, users[it] || CalendarFeed::PROVIDER_LABELS[it] || "Hệ thống" ] }
  end

  def self.room_names(versions) = Room.where(id: versions.map(&:room_id).uniq).to_h { [ it.id, it.name ] }

  def self.entry(version) = new.activity_entry(version)

  PER_PAGE = 50
  Line = Data.define(:id, :at, :kind, :action, :detail, :actor, :room_id, :room_name)

  # Newest first, PER_PAGE at a time: before = the last id of the page above (a param, ignored unless a positive integer).
  def self.page(versions, before)
    before = (Integer(before, exception: false) if before.is_a?(String))
    versions = versions.where(id: ...before) if before&.positive?
    versions.reorder(id: :desc).limit(PER_PAGE).to_a
  end

  # One Line per version, with who did it and the room's name.
  def self.lines(versions)
    actors, rooms = actors(versions), room_names(versions)
    versions.map { Line.new(id: it.id, at: it.created_at, **entry(it), actor: actors[it.whodunnit], room_id: it.room_id, room_name: rooms[it.room_id]) }
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
      in [ "Room", "destroy" ] then [ :cancel, "Xoá phòng", after["name"] ]
      in [ "Room", "update" ] then activity_room_update(changes)
      in [ "CalendarFeed", "create" | "destroy" ]
        [ :feed, version.event == "create" ? "Thêm kênh" : "Xoá kênh", CalendarFeed::PROVIDER_LABELS.fetch(after["provider"], "iCal") ]
      in [ "Payment", "create" | "destroy" ] then activity_payment(version, after)
      in [ "BookingCharge", "create" | "destroy" ]
        [ version.event == "create" ? :ok : :cancel, version.event == "create" ? "Thêm dịch vụ" : "Bỏ dịch vụ", activity_charge(after) ]
      in [ "Service", "create" ] then [ :ok, "Thêm vào danh sách dịch vụ", activity_service(after) ]
      in [ "Service", "destroy" ] then [ :cancel, "Xoá khỏi danh sách dịch vụ", activity_service(after) ]
      in [ "Service", "update" ] then [ :edit, "Sửa dịch vụ", activity_service_changes(changes, after) ]
      in [ "Guest", "create" | "update" ]
        after["flag"] ? [ :error, "Đánh dấu khách cần lưu ý", [ after["name"], after["flag"] ].compact.join(" · ") ] : [ :ok, "Bỏ đánh dấu khách", after["name"] ]
      in [ "Group", "create" ] then [ :booking, "Tạo đoàn", activity_group(after) ]
      in [ "Group", "update" ] then [ :edit, "Sửa đoàn", activity_group(after, changes) ]
      in [ "CalendarFeed", "update" ] then after["last_error"].present? ? [ :error, "Đồng bộ lỗi", CalendarFeed::ERROR_MESSAGES.fetch(CalendarFeed.error_kind(after["last_error"])) ] : [ :ok, "Đồng bộ lại được" ]
      else [ :edit, "Thay đổi" ]
      end
    { kind:, action:, detail: detail.presence }
  end

  private
    def vnd(amount) = amount && VndPrice.format(amount)

    # The record as it was right after this change (before it, for a destroy). A create's object_changes leaves out
    # attributes still at their column default (a charge's quantity 1), so those come from the defaults.
    def activity_after(version)
      return version.object.to_h if version.event == "destroy"
      before = version.event == "create" ? version.item_type.safe_constantize&.column_defaults.to_h : version.object.to_h
      before.merge(version.object_changes.to_h.transform_values(&:last))
    end

    def activity_dates(attrs) = [ attrs["start_date"], attrs["end_date"] ].map { Date.parse(it).strftime("%d/%m") }.join("–")
    def activity_stay(attrs) = [ attrs["guest_name"].presence, activity_dates(attrs) ].compact.join(" ")
    def activity_value(value) = value.presence || "—"
    def activity_ota?(version) = CalendarFeed::PROVIDER_LABELS.key?(version.whodunnit)
    # The guest's name, or the stay's dates when there is none, so a check-in says which stay it was.
    def activity_guest(attrs) = attrs["guest_name"].presence || "Khách #{activity_dates(attrs)}"

    # Thu / Hoàn tiền (#139), and a wrong entry deleted.
    def activity_payment(version, after)
      refund = after["kind"] == "refund"
      action = version.event == "destroy" ? "Xoá khoản #{refund ? "hoàn" : "thu"}" : (refund ? "Hoàn tiền" : "Thu tiền")
      [ version.event == "destroy" || refund ? :cancel : :ok, action, [ vnd(after["amount"]), Payment::METHODS[after["payment_method"]], activity_code(after) ].compact.join(" · ") ]
    end

    def activity_charge(after)
      label = "#{after["name"]} × #{after["quantity"]}#{" #{after["unit"]}" if after["unit"]}"
      [ label, vnd(after["unit_price"] * after["quantity"]), activity_code(after) ].compact.join(" · ")
    end

    def activity_service(attrs) = "#{attrs["name"]} · #{vnd(attrs["price"])}#{"/#{attrs["unit"]}" if attrs["unit"]}"

    def activity_service_changes(changes, after)
      parts = []
      parts << "đổi tên #{changes["name"][0]} → #{changes["name"][1]}" if changes.key?("name")
      parts << "giá #{vnd(changes["price"][0])} → #{vnd(changes["price"][1])}" if changes.key?("price")
      parts << "đơn vị #{activity_value(changes["unit"][0])} → #{activity_value(changes["unit"][1])}" if changes.key?("unit")
      [ (after["name"] unless changes.key?("name")), parts.join(", ") ].compact.join(": ")
    end

    # Đặt phòng theo đoàn (#164): "DOAN-0001 Đoàn Sao Mai", plus what changed.
    def activity_group(after, changes = {})
      parts = []
      parts << "đổi tên #{changes["name"][0]} → #{changes["name"][1]}" if changes.key?("name")
      { "contact" => "trưởng đoàn", "phone" => "SĐT", "origin" => "nguồn" }.each do |attr, label|
        parts << "#{label}: #{activity_value(changes[attr][0])} → #{activity_value(changes[attr][1])}" if changes.key?(attr)
      end
      parts << (after["bill"] == "split" ? "tách hoá đơn theo phòng" : "một hoá đơn cho đoàn") if changes.key?("bill")
      [ "#{format("DOAN-%04d", after["number"].to_i)} #{after["name"]}", parts.join(", ").presence ].compact.join(": ")
    end

    def activity_code(after) = Booking.where(id: after["booking_id"]).pick(:number)&.then { format("DP-%04d", it) }

    def activity_booking_update(version, changes, after)
      before = version.object.to_h
      if changes.key?("room_id")
        names = Room.where(id: changes["room_id"]).to_h { [ it.id, it.name ] }
        [ :stay, "Đổi phòng", "#{activity_guest(after)}: #{names[changes["room_id"][0]]} → #{names[changes["room_id"][1]]}" ]
      elsif changes.key?("declared_at") then [ :ok, "Khai báo lưu trú", activity_guest(after) ]
      elsif changes.key?("removed_from_feed_at")
        after["removed_from_feed_at"] ? [ :error, "OTA đã huỷ, khách đang ở", activity_guest(after) ] : [ :sync, "OTA có lại đặt phòng", activity_stay(after) ]
      elsif changes.key?("checked_in_at")
        after["checked_in_at"] ? [ :check_in, "Nhận phòng", activity_guest(after) ] : [ :cancel, "Hoàn tác nhận phòng", activity_guest(after) ]
      elsif changes.key?("checked_out_at")
        after["checked_out_at"] ? [ :check_out, "Trả phòng", activity_guest(after) ] : [ :cancel, "Hoàn tác trả phòng", activity_guest(after) ]
      elsif changes["status"]&.last == "cancelled" then [ :cancel, "Huỷ", [ activity_stay(after), after["cancel_reason"] ].compact.join(" · ") ]
      elsif changes["status"]&.first == "cancelled" then [ :booking, "Khôi phục", activity_stay(after) ]
      # "hold" only appears in history from before Giữ chỗ was removed (#127).
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
      parts << (after["pays_own"] ? "khách tự trả" : "tính vào đoàn") if changes.key?("pays_own")
      parts << "đã cọc #{vnd(changes["deposit"][0]) || "—"} → #{vnd(changes["deposit"][1]) || "—"}" if changes.key?("deposit")
      parts << "giảm giá #{vnd(changes["discount"][0]) || "—"} → #{vnd(changes["discount"][1]) || "—"}#{" (#{after["discount_reason"]})" if after["discount_reason"]}" if changes.key?("discount")
      { "price" => "giá", "weekend_price" => "giá T6–T7" }.each do |attr, label|
        parts << "#{label} #{vnd(changes[attr][0]) || "giá phòng"} → #{vnd(changes[attr][1]) || "giá phòng"}" if changes.key?(attr)
      end
      guest = after["guest_name"].presence unless changes.key?("guest_name")
      [ guest, parts.join(", ") ].compact.join(": ")
    end

    def activity_room_update(changes)
      if changes["maintenance_until"]&.last
        return [ :room, "Bảo trì", "đến #{Date.parse(changes["maintenance_until"][1]).strftime("%d/%m")} · #{changes.dig("maintenance_reason", 1) || "cùng lý do"}" ]
      elsif changes.key?("maintenance_until")
        return [ :clean, changes.key?("housekeeping") ? "Xong bảo trì" : "Hết hạn bảo trì, cần dọn" ]
      end
      return [ :clean, "Dọn xong" ] if changes.keys == [ "housekeeping" ]
      return changes["damage_note"][1] ? [ :error, "Báo hỏng / thiếu đồ", changes["damage_note"][1] ] : [ :ok, "Đã xử lý đồ hỏng" ] if changes.keys == [ "damage_note" ]
      return [ :room, changes["active"][1] ? "Nhận khách lại" : "Tạm ngưng phòng" ] if changes.keys == [ "active" ]
      parts = []
      parts << "đổi tên #{changes["name"][0]} → #{changes["name"][1]}" if changes.key?("name")
      parts << "giá #{vnd(changes["price"][0]) || "chưa có"} → #{vnd(changes["price"][1]) || "chưa có"}" if changes.key?("price")
      parts << "giá T6–T7 #{vnd(changes["weekend_price"][0]) || "như thường"} → #{vnd(changes["weekend_price"][1]) || "như thường"}" if changes.key?("weekend_price")
      parts << "tối đa #{changes["max_guests"][0]} → #{changes["max_guests"][1]} khách" if changes.key?("max_guests")
      parts << "tầng #{activity_value(changes["floor"][0])} → #{activity_value(changes["floor"][1])}" if changes.key?("floor")
      parts << "loại #{Room::ROOM_TYPES[changes["room_type"][0]] || "—"} → #{Room::ROOM_TYPES[changes["room_type"][1]] || "—"}" if changes.key?("room_type")
      parts << "sửa tiện nghi" if changes.key?("amenities")
      parts << "sửa ghi chú" if changes.key?("note")
      parts << (changes["active"][1] ? "bật phòng" : "tắt phòng") if changes.key?("active")
      parts << "dọn xong" if changes.key?("housekeeping")
      [ :room, "Sửa phòng", parts.join(", ") ]
    end
end
