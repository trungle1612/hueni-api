require "test_helper"

# Giới thiệu (#271): public, indexed and shared on Facebook; signed-in users get Vào app instead of Đăng nhập.
class Pms::IntroTest < ActionDispatch::IntegrationTest
  test "logged out: renders with SEO and Open Graph tags, Zalo sign-up, Đăng nhập" do
    get pms_intro_path
    assert_response :success
    assert_select "html[lang=vi]"
    assert_select "h1", count: 1
    assert_select "link[rel=canonical][href=?]", "https://api.hueni.me/gioi-thieu"
    assert_select "meta[name=description][content]"
    %w[og:title og:description og:url og:image og:locale].each { |property| assert_select "meta[property=?][content]", property }
    assert_select "meta[property='og:image'][content=?]", "https://api.hueni.me/gioi-thieu.png"
    assert_select "form[action='/auth/zalo2?register=1'] button", text: "Đăng ký bằng Zalo"
    assert_select "a[href=?]", new_session_path, text: "Đăng nhập"
    assert_select "a[href=?]", pms_today_path, count: 0
    assert_select "nav[aria-label='Điều hướng chính']", count: 0
    assert_no_match(/Mini App|Bảng giá/, response.body)
  end

  test "signed in: renders, Vào app replaces Đăng nhập and the sign-up button" do
    log_in users(:owner)
    get pms_intro_path
    assert_response :success
    assert_select "a[href=?]", pms_today_path, text: "Vào app"
    assert_select "a[href=?]", new_session_path, count: 0
    assert_select "form[action='/auth/zalo2?register=1']", count: 0
    assert_select "nav[aria-label='Điều hướng chính']", count: 0
  end

  test "Điều khoản is public; the login page links to Giới thiệu" do
    get pms_legal_path(doc: "privacy", co_so: "x")
    assert_response :success
    assert_select "#consent", count: 0
    assert_select "a[aria-label='Quay lại'][href=?]", pms_intro_path

    get new_session_path
    assert_select "a[href=?]", pms_intro_path
  end
end
