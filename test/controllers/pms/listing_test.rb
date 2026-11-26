require "test_helper"

# Hiển thị trên hue-ni in the PWA (#283): the site_* settings, checklist and preview, owners only.
class Pms::ListingTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12) # limdim booked 01–03/10
    rooms(:garden).update!(room_type: "double", price: 400_000)
    rooms(:limdim).update!(room_type: "family", price: 600_000)
    @place = places(:tomo)
  end

  def listing(**attrs) = { listing: { open: "1", mode: "approve", reply_minutes: "30", cutoff_hour: "20", deposit_percent: "30", hold_minutes: "30",
    show_phone: "0", shown_room_ids: [ rooms(:garden).id, rooms(:limdim).id ], **attrs } }

  test "missing checklist items: switch disabled, each marked with what's missing; turning on is refused" do
    log_in users(:owner)
    get pms_more_path
    assert_select "main a[href=?]", pms_listing_path, text: /Hiển thị trên hue-ni\s*Đang tạm dừng nhận yêu cầu/
    get pms_listing_path
    assert_response :success
    assert_select "input[type=checkbox][name='listing[open]'][disabled]"
    assert_select "main", text: /Hoàn thành các mục còn thiếu bên dưới để bật hiển thị/
    assert_select "#h-checks", text: /0 \/ 4 đã xong/
    assert_select "#check_photos[href=?]", pms_rooms_path, text: /!\s*Ảnh homestay\s*Cần ảnh cho mỗi phòng hiển thị/
    assert_select "#check_map", text: /Chưa có vị trí/
    assert_select "#check_rules[popovertarget=rules_sheet]", text: /Cần giờ nhận, trả phòng/
    assert_select "#check_bank[href=?]", pms_settings_path, text: /Cần tài khoản chuyển khoản/
    assert_select "#preview", text: /Liên hệ để hỏi phòng/

    patch pms_listing_path, params: listing
    assert_response :unprocessable_entity
    assert_select "#listing_errors", text: /cần vị trí trên bản đồ/
    assert_not @place.reload.site_open
  end

  test "owner sets rules, turns the listing on and saves; booking_site answers with it" do
    site_ready(@place)
    @place.update!(check_in_time: nil)
    log_in users(:owner)

    patch pms_listing_rules_path, params: { place: { check_in_time: "25:00", house_rules: "Không hút thuốc." } }
    assert_response :unprocessable_entity
    assert_select "#rules_sheet[data-controller=open] #check_in_time_error", text: /phải theo dạng 14:00/
    assert_select "#check_rules", text: /!.*Cần giờ nhận, trả phòng/m
    assert_select "input[name='listing[open]'][disabled]"
    patch pms_listing_rules_path, params: { place: { check_in_time: "14:00", check_out_time: "12:00", house_rules: "Không hút thuốc." } }
    assert_redirected_to pms_listing_path
    follow_redirect!
    assert_select ".pms-toast", text: "Đã cập nhật. hue-ni hiển thị thay đổi trong vài phút."
    assert_select "#h-checks", text: /4 \/ 4 đã xong/
    assert_select "#check_rules", text: /✓.*14:00 \/ 12:00/m
    assert_select "input[name='listing[open]']:not([disabled])"
    assert_select "#room_#{rooms(:garden).id}[checked]"
    assert_select "main", text: /Garden · 400.000đ\s*Còn trống tối nay/
    assert_select "main", text: /Limdim · 600.000đ\s*Hết phòng tối nay/

    patch pms_listing_path, params: listing(mode: "auto", reply_minutes: "15", show_phone: "1", shown_room_ids: [ rooms(:garden).id ])
    assert_redirected_to pms_listing_path
    assert_equal [ true, "auto", 15, true, [ rooms(:limdim).id ] ],
      @place.reload.values_at(:site_open, :site_mode, :site_reply_minutes, :site_show_phone, :site_hidden_room_ids)
    follow_redirect!
    assert_select "main", text: /Đang hiện và nhận yêu cầu/
    assert_select "#preview", text: /Còn phòng.*Giá từ\s*400.000đ \/ đêm.*Đặt phòng/m

    get v1_booking_site_path(@place.slug, from: "2026-10-01", to: "2026-10-02")
    body = response.parsed_body
    assert_equal [ true, "auto" ], body.values_at("open", "mode")
    assert_equal [ "double" ], body["room_types"].pluck("key")
  end

  test "one row per room, typed or not; a room is switched off on its own (#302)" do
    rooms(:limdim).update!(room_type: "double")
    @place.rooms.create!(name: "Sen", max_guests: 2)
    site_ready(@place)
    @place.save!
    log_in users(:owner)
    get pms_listing_path
    assert_select "#h-rooms ~ div input[name='listing[shown_room_ids][]']", count: 3
    assert_select "main", text: /Sen · chưa có giá/

    patch pms_listing_path, params: listing(shown_room_ids: [ rooms(:limdim).id ])
    assert_redirected_to pms_listing_path
    assert_equal [ rooms(:garden).id, @place.rooms.find_by(name: "Sen").id ].sort, @place.reload.site_hidden_room_ids.sort
    assert_equal [ rooms(:limdim) ], @place.site_rooms.to_a
  end

  test "turning off every room while on is refused" do
    site_ready(@place)
    @place.update!(site_open: true)
    log_in users(:owner)
    patch pms_listing_path, params: listing(shown_room_ids: nil)
    assert_response :unprocessable_entity
    assert_select "#listing_errors", text: /cần ít nhất một phòng hiển thị/
    assert_select "#preview", text: /Tối nay · T5 01\/10\s*Còn phòng.*Giá từ\s*400.000đ/m
    assert_equal [], @place.reload.site_hidden_room_ids
  end

  test "rules refused by the listing's own checks say why in the sheet" do
    site_ready(@place)
    @place.update!(site_open: true)
    @place.rooms.update_all(active: false)
    log_in users(:owner)
    patch pms_listing_rules_path, params: { place: { house_rules: "Giữ yên lặng sau 22:00." } }
    assert_response :unprocessable_entity
    assert_select "#rules_sheet[data-controller=open] #rules_listing_errors", text: /cần ít nhất một phòng hiển thị.*tạm dừng hiển thị/m
    assert_equal "Không hút thuốc trong phòng.", @place.reload.house_rules
  end

  test "after the same-day cutoff the preview shows tomorrow night" do
    travel_to Time.zone.local(2026, 10, 1, 21)
    site_ready(@place)
    @place.update!(site_open: true)
    log_in users(:owner)
    get pms_listing_path
    assert_select "main", text: /Limdim · 600.000đ\s*Hết phòng đêm mai/
    assert_select "#preview", text: /Đêm mai · T6 02\/10\s*Còn phòng/
  end

  test "staff get 403; a homestay of someone else stays untouched; no homestay is 404" do
    @place.place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
    get pms_more_path
    assert_select "main a[href=?]", pms_listing_path, count: 0
    get pms_listing_path
    assert_response :forbidden
    patch pms_listing_path, params: listing(open: "0", mode: "auto")
    assert_response :forbidden
    patch pms_listing_rules_path, params: { place: { house_rules: "X" } }
    assert_response :forbidden
    assert_equal [ "approve", nil ], @place.reload.values_at(:site_mode, :house_rules)

    other = places(:hiuhill)
    log_in users(:owner)
    # ?co_so= of a homestay the user isn't in is ignored: the request stays on their own homestay.
    patch pms_listing_path(co_so: other.slug), params: listing(open: "0", mode: "auto")
    assert_redirected_to pms_listing_path
    assert_equal [ "approve", "auto" ], [ other.reload.site_mode, @place.reload.site_mode ]

    @place.place_memberships.where(user: users(:owner)).delete_all
    patch pms_listing_path, params: listing(open: "0")
    assert_response :not_found
    patch pms_listing_rules_path, params: { place: { house_rules: "X" } }
    assert_response :not_found
  end
end
