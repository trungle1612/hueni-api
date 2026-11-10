require "test_helper"

class RollbarTest < ActiveSupport::TestCase
  test "disabled without a token" do
    assert_not Rollbar.configuration.enabled
  end

  test "scrubs every filtered parameter, q included" do
    filters = Rails.application.config.filter_parameters.grep_v(Regexp)
    assert_empty filters - Rollbar.configuration.scrub_fields
    assert_includes Rollbar.configuration.scrub_fields, :q

    env = Rack::MockRequest.env_for("/admin/tim?q=Nguyen+Van+A&page=2")
    env["action_dispatch.parameter_filter"] = Rails.application.config.filter_parameters
    request = Class.new { include Rollbar::RequestDataExtractor }.new.extract_request_data_from_rack(env)

    assert_no_match "Nguyen", request.to_s
    assert_equal "2", request[:GET]["page"]
  end

  test "a failed Solid Queue job reports to Rollbar" do
    payloads = []
    capture = proc { |options| payloads << options[:payload] }
    Rollbar.configure do |config|
      config.enabled = true
      config.access_token = "test-token"
      config.transmit = false
      config.transform << capture
    end

    SolidQueue.on_thread_error.call(RuntimeError.new("sync failed"))

    data = payloads.sole["data"]
    assert_equal "test", data[:environment]
    assert_equal "sync failed", data[:body][:trace][:exception][:message]
  ensure
    Rollbar.configure do |config|
      config.enabled = false
      config.access_token = nil
      config.transmit = true
      config.transform.delete(capture)
    end
  end
end
