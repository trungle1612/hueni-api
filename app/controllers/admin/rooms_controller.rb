class Admin::RoomsController < Admin::BaseController
  before_action :set_place, only: %i[new create]
  before_action :set_room, only: %i[edit update clean]
  before_action -> { authorize!(:manage, @place) }, except: :clean

  def new
    @room = @place.rooms.build(active: true)
  end

  def create
    @room = @place.rooms.build(room_params)
    if @room.save
      redirect_to admin_place_path(@place.slug), notice: "Đã lưu phòng."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @room.update(room_params)
      redirect_to admin_place_path(@room.place.slug), notice: "Đã lưu phòng."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Staff too: cleaning is day-to-day work, not an owner-only room change.
  def clean
    @room.clean!
    redirect_back_or_to admin_place_path(@place.slug), notice: "Đã dọn xong #{@room.name}."
  end

  private
    def set_place
      @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    end

    def set_room
      @room = Current.user.accessible_rooms.find(params[:id])
      @place = @room.place
    end

    def room_params
      params.expect(room: [ :name, :max_guests, :price, :active ])
    end
end
