require "test_helper"

# Bắt đầu (#266): once per browser after login; owners get Chuẩn bị cơ sở, which also stays on Hôm nay until a room exists.
class Pms::OnboardingTest < ActionDispatch::IntegrationTest
  def push!
    WebPush.key = OpenSSL::PKey::EC.generate("prime256v1")
    yield
  ensure
    WebPush.key = nil
  end

  test "the first Hôm nay in a browser opens Bắt đầu once" do
    log_in users(:owner)
    cookies.delete("pms_onboarded")
    get pms_today_path
    assert_redirected_to pms_onboarding_path
    follow_redirect!
    assert_response :success
    get pms_today_path
    assert_response :success
  end

  test "owner: install and setup steps, Bỏ qua to Hôm nay; notifications only with Web Push" do
    log_in users(:owner)
    get pms_onboarding_path
    assert_select "section[data-step]", count: 2
    assert_select "section[data-step=install] h1", "Đặt hueni ra màn hình chính"
    assert_select "section[data-step=setup] #setup", text: /Phòng và giá.*Mời nhân viên/m
    assert_select "a[href=?]", pms_today_path, text: "Bỏ qua"
    assert_select "nav", count: 0

    push! { get pms_onboarding_path }
    assert_select "section[data-step]", count: 3
    assert_select "section[data-step=notif] button[data-action='push#enable']", "Bật thông báo"
  end

  test "staff: no setup step; the last step goes to Hôm nay" do
    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    log_in staff
    push! { get pms_onboarding_path }
    assert_select "section[data-step]", count: 2
    assert_select "section[data-step=setup]", count: 0
    assert_select "section[data-step=notif] button", text: "Vào Hôm nay"
  end

  test "Chuẩn bị cơ sở on Hôm nay for an owner until the homestay has a room; never for staff" do
    log_in users(:owner)
    get pms_today_path
    assert_select "#setup", count: 0

    Room.where(place: places(:tomo)).update_all(place_id: places(:hiuhill).id)
    get pms_today_path
    assert_select "#setup a[href=?]", new_pms_room_path, text: /Phòng và giá/
    get pms_onboarding_path
    assert_select "a[href=?]", new_pms_room_path, text: "Bắt đầu: thêm phòng"

    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    log_in staff
    get pms_today_path
    assert_select "#setup", count: 0
  end

  test "no homestay: no Bắt đầu redirect" do
    user = User.create!(name: "Khách", phone_number: "0987333444", password: "password123")
    log_in user
    cookies.delete("pms_onboarded")
    get pms_today_path
    assert_response :success
  end
end
