require "test_helper"

# Thông báo hệ thống (#213): admins write announcements for every Mini App user.
class Admin::AnnouncementsControllerTest < ActionDispatch::IntegrationTest
  PARAMS = { kind: "maintenance", title: "Bảo trì 02:00 – 02:30", summary: "Ứng dụng tạm ngưng 30 phút.",
             content: "## Bị ảnh hưởng\n- Không đồng bộ kênh", published_at: "2026-11-08T09:00" }.freeze

  test "an admin posts, edits and deletes an announcement under menu Thông báo" do
    log_in users(:admin)
    get admin_announcements_path
    assert_response :success
    assert_select "a.menu-active[href=?]", admin_announcements_path

    post admin_announcements_path, params: { announcement: PARAMS }
    assert_redirected_to admin_announcements_path
    announcement = Announcement.sole
    assert_equal [ "maintenance", "Bảo trì 02:00 – 02:30" ], announcement.values_at(:kind, :title)

    post admin_announcements_path, params: { announcement: PARAMS.merge(title: "", cta: "Mở", cta_path: "https://x.example") }
    assert_response :unprocessable_entity
    assert_equal 1, Announcement.count

    get edit_admin_announcement_path(announcement)
    assert_response :success
    patch admin_announcement_path(announcement), params: { announcement: { title: "Bảo trì CN 09/11" } }
    assert_equal "Bảo trì CN 09/11", announcement.reload.title

    delete admin_announcement_path(announcement)
    assert_not Announcement.exists?(announcement.id)
  end

  test "with Web Push on, the form says it is pushed once and the list shows when it was" do
    WebPush.key = OpenSSL::PKey::EC.generate("prime256v1")
    log_in users(:admin)
    get admin_announcements_path
    assert_select "p", text: /gửi một lần đến điện thoại/
    announcement = Announcement.create!(PARAMS.merge(published_at: 1.hour.ago))
    announcement.update!(pushed_at: Time.current)
    get admin_announcements_path
    assert_select "##{dom_id(announcement)}", text: /đã gửi đến điện thoại/
    get edit_admin_announcement_path(announcement)
    assert_select "p", text: /Đã gửi đến điện thoại lúc .*sửa không gửi lại/
  ensure
    WebPush.key = nil
  end

  test "owners are sent to the PWA and change nothing" do
    announcement = Announcement.create!(PARAMS)
    log_in users(:owner)
    get admin_announcements_path
    assert_redirected_to pms_today_path
    delete admin_announcement_path(announcement)
    assert_redirected_to pms_today_path
    assert Announcement.exists?(announcement.id)
  end
end
