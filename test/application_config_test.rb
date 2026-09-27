require "test_helper"

class ApplicationConfigTest < ActiveSupport::TestCase
  test "uses Huế time zone" do
    assert_equal "Asia/Ho_Chi_Minh", Time.zone.tzinfo.identifier
  end

  test "defaults to Vietnamese locale" do
    assert_equal :vi, I18n.default_locale
  end

  test "has Vietnamese translations for built-in messages" do
    assert_equal "không thể để trắng", I18n.t("errors.messages.blank", locale: :vi)
  end
end
