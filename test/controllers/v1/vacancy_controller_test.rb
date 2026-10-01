require "test_helper"

class V1::VacancyControllerTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 10, 1, 12) } # limdim booked, garden free

  test "returns today's vacancy per place" do
    get "/v1/vacancy"

    assert_response :success
    assert_equal({ "date" => "2026-10-01", "places" => { "tomo-homestay" => { "left" => 1, "max_guests" => 2 } } }, response.parsed_body)
    assert_equal "max-age=60, public", response.headers["Cache-Control"]
  end

  test "allows CORS from hueni origins only" do
    get "/v1/vacancy", headers: { "Origin" => "https://hueni.me" }
    assert_equal "https://hueni.me", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers["Vary"], "Origin"

    get "/v1/vacancy", headers: { "Origin" => "http://localhost:5173" }
    assert_equal "http://localhost:5173", response.headers["Access-Control-Allow-Origin"]

    get "/v1/vacancy", headers: { "Origin" => "https://evil.example" }
    assert_nil response.headers["Access-Control-Allow-Origin"]
  end

  test "exposes no guest or feed data" do
    bookings(:limdim_confirmed).update!(guest_phone: "0905123456", note: "secret", uid: "abc@airbnb.com")
    get "/v1/vacancy"

    [ "Anh Minh", "0905123456", "secret", "abc@airbnb.com", calendar_feeds(:limdim_airbnb).url ].each { assert_not_includes response.body, it }
  end

  test "cache is busted when a booking is written" do
    original, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new

    get "/v1/vacancy"
    assert_equal 1, response.parsed_body.dig("places", "tomo-homestay", "left")

    Booking.create!(room: rooms(:garden), start_date: "2026-10-01", end_date: "2026-10-02", status: "hold")
    get "/v1/vacancy"
    assert_equal 0, response.parsed_body.dig("places", "tomo-homestay", "left")
  ensure
    Rails.cache = original
  end
end
