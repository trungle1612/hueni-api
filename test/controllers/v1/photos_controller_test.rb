require "test_helper"

# Ảnh phòng for hueni.me (#187): public, active rooms with photos only.
class V1::PhotosControllerTest < ActionDispatch::IntegrationTest
  test "lists active rooms' photo URLs, cacheable, CORS for hueni.me; unknown slug 404" do
    photo = Rack::Test::UploadedFile.new(file_fixture("room.jpg"), "image/jpeg")
    rooms(:garden).update!(room_type: "double", photo_files: [ photo, photo ])
    rooms(:limdim).update!(active: false, photo_files: [ photo ])
    urls = rooms(:garden).photos.reload.map(&:url)

    get "/v1/places/tomo-homestay/photos", headers: { "Origin" => "https://hueni.me" }
    assert_response :success
    assert_equal({ "rooms" => [ { "id" => rooms(:garden).id, "name" => "Garden", "room_type" => "double", "bookable" => false, "photos" => urls } ] }, response.parsed_body)
    assert_equal "max-age=300, public", response.headers["Cache-Control"]
    assert_equal "https://hueni.me", response.headers["Access-Control-Allow-Origin"]

    site_ready(places(:tomo))
    places(:tomo).update!(site_open: true)
    get "/v1/places/tomo-homestay/photos"
    assert_equal [ true ], response.parsed_body["rooms"].pluck("bookable"), "open, its type shown: bookable as itself"

    get "/v1/places/hiuhill-homestay/photos"
    assert_equal({ "rooms" => [] }, response.parsed_body)
    get "/v1/places/nope/photos"
    assert_response :not_found
  end
end
