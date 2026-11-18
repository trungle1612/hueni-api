require "test_helper"

# Ảnh phòng (#187): resized WebP files under photos_root, metadata stripped, at most 10 per room.
class RoomPhotoTest < ActiveSupport::TestCase
  setup { @room = rooms(:garden) }

  def photo = Rack::Test::UploadedFile.new(file_fixture("room.jpg"), "image/jpeg")

  test "writes a resized WebP without EXIF at its public URL" do
    assert Vips::Image.new_from_file(file_fixture("room.jpg").to_s).get_fields.include?("exif-ifd3-GPSLatitude")
    assert @room.update(photo_files: [ photo, photo ])
    first, second = @room.photos.reload

    assert_equal [ 1, 2 ], [ first.position, second.position ]
    assert_match %r{\Ahttps://hueni.me/images/places/tomo-homestay/rooms/#{@room.id}/\h{16}\.webp\z}, first.url
    assert_not_equal first.key, second.key
    image = Vips::Image.new_from_file(first.path.to_s)
    assert_equal [ "webpload", 1600, 800 ], [ image.get("vips-loader"), image.width, image.height ]
    assert_empty image.get_fields.grep(/exif|xmp|iptc/)
    assert_equal "644", format("%o", first.path.stat.mode & 0o777)
  end

  test "the 11th photo, a non-image and a too large file are refused on the room" do
    RoomPhoto.insert_all(10.times.map { { room_id: @room.id, key: "k#{it}", position: it } })
    assert_not @room.reload.update(photo_files: [ photo ])
    assert_equal [ "Ảnh phòng tối đa 10 ảnh mỗi phòng" ], @room.errors.full_messages
    RoomPhoto.where(room: @room).delete_all

    text = Rack::Test::UploadedFile.new(file_fixture("empty.ics"), "image/jpeg")
    assert_not @room.reload.update(photo_files: [ text ])
    assert_equal [ "Ảnh phòng chỉ nhận JPEG, PNG, WebP hoặc HEIC" ], @room.errors.full_messages

    big = photo.tap { it.define_singleton_method(:size) { RoomPhoto::MAX_BYTES + 1 } }
    assert_not @room.reload.update(photo_files: [ big ])
    assert_equal [ "Ảnh phòng quá lớn, mỗi ảnh tối đa 20 MB" ], @room.errors.full_messages
    assert_not @room.reload.update(photo_files: [ "a string" ])
    assert_equal 0, @room.photos.count
  end

  test "deleting a photo or the room deletes the file" do
    @room.update!(photo_files: [ photo, photo ])
    first, second = @room.photos.to_a
    first.destroy!
    assert_not first.path.exist?
    assert second.path.exist?

    @room.destroy!
    assert_not second.path.exist?
  end
end
