# Phòng (#233): the current homestay's rooms with today's state (RoomDay) and Tình trạng for anyone at the desk;
# Thêm / sửa / xoá phòng for owners, with the same model rules as the Mini App (MiniApp::V1::RoomsController).
class Pms::RoomsController < Pms::BaseController
  FILTERS = { "co-khach" => "Có khách", "can-don" => "Cần dọn", "san-sang" => "Sẵn sàng", "bao-tri" => "Bảo trì" }.freeze

  before_action :set_room, only: %i[edit update destroy status]
  before_action :set_place, only: %i[new create]
  before_action -> { authorize!(:manage, @place) }, only: %i[new create edit update destroy]
  before_action -> { authorize!(:operate, @place) }, only: :status

  def index
    return unless current_place
    days = RoomDay.for(current_place.rooms.order(:floor, :name))
    @query = params[:q].to_s.strip
    folded = Booking.search_fold(@query)
    searched = days.select { [ it.room.name, it.booking&.label, it.next_booking&.label ].compact.any? { Booking.search_fold(it).include?(folded) } }
    @counts = FILTERS.keys.to_h { |key| [ key, searched.count { helpers.pms_room_filter(it) == key } ] }
    @filter = params[:loc].presence_in(FILTERS.keys)
    @days = @filter ? searched.select { helpers.pms_room_filter(it) == @filter } : searched
    @all = searched.size
  end

  def new
    @room = @place.rooms.build(max_guests: 2)
  end

  def create
    @room = @place.rooms.build(room_params)
    if @room.save
      redirect_to pms_rooms_path, status: :see_other, flash: { toast: "Đã thêm phòng #{@room.name}" }
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @room.update(room_params)
      redirect_to pms_rooms_path, status: :see_other, flash: { toast: [ "Đã lưu phòng #{@room.name}.", *@room.change_notes ].join(" ") }
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Xoá phòng: the model refuses a room that ever had a booking.
  def destroy
    if @room.destroy
      redirect_to pms_rooms_path, status: :see_other, flash: { toast: "Đã xoá phòng #{@room.name}" }
    else
      redirect_to edit_pms_room_path(@room), status: :see_other, alert: @room.errors.full_messages.to_sentence
    end
  end

  # Tình trạng (staff too): Sẵn sàng / Cần dọn / Bảo trì with its reason and last day; Đã dọn = Sẵn sàng.
  def status
    if @room.update(params.expect(room: %i[housekeeping maintenance_reason maintenance_until]))
      flash[:toast] = @room.maintenance? ? "Phòng #{@room.name} bảo trì đến #{@room.maintenance_until.strftime("%d/%m")}" :
        "Phòng #{@room.name}: #{@room.clean? ? "đã dọn, sẵn sàng đón khách" : "cần dọn"}"
    else
      flash[:alert] = @room.errors.full_messages.to_sentence
    end
    redirect_back_or_to pms_rooms_path, status: :see_other
  end

  private
    def set_place
      @place = current_place or raise ActiveRecord::RecordNotFound
    end

    def set_room
      @room = Current.user.accessible_rooms.find(params[:id])
      @place = @room.place
    end

    def room_params
      params.expect(room: [ :name, :floor, :room_type, :max_guests, :price, :weekend_price, :active, :note, amenities: [], photo_files: [] ])
    end
end
