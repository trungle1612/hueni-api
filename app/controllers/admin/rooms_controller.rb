class Admin::RoomsController < Admin::BaseController
  before_action :set_place, only: %i[new create]
  before_action :set_room, only: %i[edit update clean]
  before_action -> { authorize!(:manage, @place) }, except: %i[index clean]
  before_action -> { authorize!(:operate, @place) }, only: :clean

  # Room setup for every homestay you own; the homestay page stays the daily board.
  def index
    @places = owned_places.includes(rooms: :calendar_feeds)
    raise Forbidden if @places.none?
  end

  def new
    @room = @place.rooms.build(max_guests: 2)
  end

  def create
    @room = @place.rooms.build(room_params)
    if @room.save
      # Straight to Kênh OTA: linking the Airbnb / Booking.com calendar is the usual next step.
      flash[:room_added] = true
      redirect_to edit_admin_room_path(@room, anchor: "kenh-ota")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @room.update(room_params)
      redirect_to admin_rooms_path(anchor: @place.slug), notice: [ "Đã lưu phòng #{@room.name}.", *price_notes ].join(" ")
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
      params.expect(room: [ :name, :max_guests, :price, :weekend_price, :active ])
    end

    def price_notes
      return [] unless @room.saved_change_to_price? || @room.saved_change_to_weekend_price?
      kept = @room.quoted_bookings.count
      [ ("#{kept} đặt phòng sắp tới giữ giá cũ." if kept.positive?),
        ("Giá thứ 6, thứ 7 đang thấp hơn ngày thường, kiểm tra lại nếu không cố ý." if @room.weekend_price_below_price?) ].compact
    end
end
