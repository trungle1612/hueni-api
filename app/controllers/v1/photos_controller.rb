# Ảnh phòng (#187) for hueni.me: active rooms with at least one photo. The URLs are files on hueni.me itself.
class V1::PhotosController < V1::BaseController
  rate_limit to: 60, within: 1.minute

  def show
    place = Place.find_by!(slug: params[:slug])
    rooms = place.rooms.where(active: true).where.associated(:photos).distinct.includes(:photos).order(:name)
    expires_in 5.minutes, public: true
    render json: { rooms: rooms.map { { name: it.name, room_type: it.room_type, photos: it.photos.map(&:url) } } }
  end
end
