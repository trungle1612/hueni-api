require "test_helper"

# Recent Chrome reports a node detached by a Turbo page swap as UnknownError ("Node with given id does not
# belong to the document") instead of StaleElementReferenceError; let Capybara retry it the same way (#133).
Capybara::Selenium::Driver.prepend(Module.new do
  def invalid_element_errors = super + [ Selenium::WebDriver::Error::UnknownError ]
end)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # Mocked Zalo login (#97); the server runs in this process, so the mock reaches it. Default: Chị Lan.
  def log_in_with_zalo(uid = "zalo-chi-lan")
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid:)
    visit new_session_path
    click_button "Đăng nhập bằng Zalo"
    assert_selector "h1", text: "Tổng quan"
  end
end
