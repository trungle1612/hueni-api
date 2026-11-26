ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)
OmniAuth.config.test_mode = true

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Hiển thị trên hue-ni (#282): what the checklist asks for, so site_open can be turned on. Photo rows only, no files.
    def site_ready(place)
      place.rooms.each { RoomPhoto.insert({ room_id: it.id, key: SecureRandom.hex(8), position: 1 }) }
      place.assign_attributes(lat: 16.46, lng: 107.58, check_in_time: "14:00", check_out_time: "12:00", house_rules: "Không hút thuốc trong phòng.",
        bank_name: "Vietcombank", bank_account: "0123456789", bank_holder: "NGUYEN THI LAN")
    end
  end
end
