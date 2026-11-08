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

  test "owners get 404 and no menu entry" do
    announcement = Announcement.create!(PARAMS)
    log_in users(:owner)
    get admin_root_path
    assert_select "a[href=?]", admin_announcements_path, count: 0
    get admin_announcements_path
    assert_response :not_found
    delete admin_announcement_path(announcement)
    assert_response :not_found
    assert Announcement.exists?(announcement.id)
  end
end
