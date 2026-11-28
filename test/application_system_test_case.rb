require "test_helper"

# Recent Chrome reports a node detached by a Turbo page swap as UnknownError ("Node with given id does not
# belong to the document") instead of StaleElementReferenceError; let Capybara retry it the same way (#133).
Capybara::Selenium::Driver.prepend(Module.new do
  def invalid_element_errors = super + [ Selenium::WebDriver::Error::UnknownError ]
end)

# Chrome 158 rejects origin "*" in the Storage.clearDataForOrigin that Capybara's reset! sends ("* is not a valid URL"),
# so every test errored in teardown; clear the cookies it asked for directly.
Capybara::Selenium::Driver::ChromeDriver.prepend(Module.new do
  def execute_cdp(cmd, **params)
    return super unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"
    super("Network.clearBrowserCookies")
  end
end)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # Bắt đầu (#266) already seen in this browser, so a login lands where the test expects; delete the cookie to test it.
  setup do
    visit rails_health_check_path
    page.driver.browser.manage.add_cookie(name: "pms_onboarded", value: "1")
  end

  # Mocked Zalo login (#97); the server runs in this process, so the mock reaches it. Default: Chị Lan.
  def log_in_with_zalo(uid = "zalo-chi-lan")
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid:)
    visit new_session_path
    click_button "Đăng nhập bằng Zalo"
    assert_no_current_path new_session_path
  end
end
