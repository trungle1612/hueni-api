# Loại phòng (#138): owners manage their homestay's list on Phòng.
class Admin::RoomTypesController < Admin::BaseController
  before_action do
    @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    authorize!(:manage, @place)
  end
  before_action -> { @room_type = @place.room_types.find(params[:id]) }, only: %i[update destroy]

  def create
    save @place.room_types.build(room_type_params), "Đã thêm loại phòng"
  end

  def update
    @room_type.assign_attributes(room_type_params)
    save @room_type, "Đã lưu loại phòng"
  end

  def destroy
    if @room_type.destroy
      back notice: "Đã xoá loại phòng #{@room_type.name}."
    else
      back alert: "#{@room_type.name} đang có phòng dùng, đổi loại của các phòng đó trước."
    end
  end

  private
    def room_type_params = params.expect(room_type: [ :name ])

    def save(room_type, message)
      room_type.save ? back(notice: "#{message} #{room_type.name}.") : back(alert: room_type.errors.full_messages.to_sentence)
    end

    def back(**flash) = redirect_to(admin_rooms_path(anchor: "loai-phong-#{@place.slug}"), **flash)
end
