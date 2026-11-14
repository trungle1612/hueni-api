require "test_helper"

# The PMS PWA shell (#228): layout, homestay switcher, 404 inside the PWA, manifest and service worker.
class Pms::ShellTest < ActionDispatch::IntegrationTest
  test "requires login and comes back to the PWA after the Zalo login" do
    get pms_today_path
    assert_redirected_to new_session_path

    log_in users(:owner)
    assert_redirected_to pms_today_url
    follow_redirect!
    assert_select "h1", "Hôm nay"
  end

  test "shows the homestay in the top bar and the PWA chrome" do
    log_in users(:owner)
    get pms_today_path
    assert_response :success
    assert_select "link[rel=manifest][href='/manifest.json']"
    assert_select "header", text: /tomo homestay/
    assert_select "nav[aria-label='Điều hướng chính'] a[aria-current=page]", text: "Hôm nay"
  end

  test "switches homestay among the user's own" do
    PlaceMembership.create!(user: users(:owner), place: places(:hiuhill), role: "staff")
    log_in users(:owner)

    patch pms_place_path("hiuhill-homestay")
    assert_redirected_to pms_today_path
    follow_redirect!
    assert_select "header", text: /Hiu Hill Homestay/
  end

  test "another owner's homestay is a 404 inside the PWA" do
    log_in users(:owner)
    patch pms_place_path("hiuhill-homestay")
    assert_response :not_found
    assert_select "link[rel=manifest]"
    assert_select "h2", "Không tìm thấy"
  end

  test "a user without a homestay sees an empty state" do
    sign_in_as users(:admin)
    get pms_today_path
    assert_response :success
    assert_select "h2", "Bạn chưa thuộc cơ sở nào"
  end

  test "Thêm lists homestays and logs out" do
    log_in users(:owner)
    get pms_more_path
    assert_response :success
    assert_select "button", "Đăng xuất"

    delete session_path
    get pms_today_path
    assert_redirected_to new_session_path
  end

  test "manifest and service worker are public" do
    get "/manifest.json"
    assert_response :success
    manifest = JSON.parse(response.body)
    assert_equal "/hom-nay", manifest["start_url"]
    assert_equal "standalone", manifest["display"]

    get "/service-worker.js"
    assert_response :success
    assert_includes response.body, "/offline.html"
  end
end
