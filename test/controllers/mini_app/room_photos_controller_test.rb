require "test_helper"

# Ảnh phòng in the Mini App (#187): owners upload and delete; the room JSON lists photos.
class MiniApp::RoomPhotosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: users(:owner).api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" })
  def photo = fixture_file_upload("room.jpg", "image/jpeg")

  test "owner uploads and deletes; room JSON has photos; refusals on errors.photos" do
    as :owner, :post, api_v1_room_photos_path(rooms(:garden)), { photo: }
    assert_response :created
    created = rooms(:garden).photos.sole
    assert_equal [ { "id" => created.id, "url" => created.url } ], response.parsed_body["photos"]

    as :owner, :get, rooms_api_v1_place_path(places(:tomo))
    assert_equal [ created.url ], response.parsed_body["rooms"].find { it["id"] == rooms(:garden).id }["photos"].pluck("url")

    as :owner, :post, api_v1_room_photos_path(rooms(:garden)), { photo: fixture_file_upload("empty.ics", "image/jpeg") }
    assert_response :unprocessable_entity
    assert_equal({ "photos" => [ "Ảnh phòng chỉ nhận JPEG, PNG, WebP hoặc HEIC" ] }, response.parsed_body["errors"])
    as :owner, :post, api_v1_room_photos_path(rooms(:garden))
    assert_response :bad_request

    as :owner, :delete, api_v1_room_photo_path(rooms(:garden), created)
    assert_response :success
    assert_equal [], response.parsed_body["photos"]
    assert_not created.path.exist?
  end

  test "staff 403, another owner's room 404" do
    created = rooms(:garden).photos.create!(file: photo)
    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2, photo_files: [ photo ])
    as :staff, :post, api_v1_room_photos_path(rooms(:garden)), { photo: }
    assert_response :forbidden
    as :staff, :delete, api_v1_room_photo_path(rooms(:garden), created)
    assert_response :forbidden
    as :owner, :post, api_v1_room_photos_path(other), { photo: }
    assert_response :not_found
    as :owner, :delete, api_v1_room_photo_path(rooms(:garden), other.photos.first)
    assert_response :not_found
    assert_equal 2, RoomPhoto.count
  end
end
