# Never read anywhere; Ảnh phòng (#187) are room_photos.
class RemovePhotoUrlsFromRooms < ActiveRecord::Migration[8.1]
  def change
    remove_column :rooms, :photo_urls, :json, default: [], null: false
  end
end
