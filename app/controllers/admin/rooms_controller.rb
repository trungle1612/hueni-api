class Admin::RoomsController < Admin::BaseController
  before_action :set_place, only: %i[new create]
  before_action :set_room, only: %i[edit update destroy clean maintenance]
  before_action -> { authorize!(:manage, @place) }, except: %i[index clean maintenance]
  before_action -> { authorize!(:operate, @place) }, only: %i[clean maintenance]

  # Room setup for every homestay you own; the homestay page stays the daily board.
  def index
    @places = owned_places.includes(:room_types, rooms: %i[calendar_feeds room_type])
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
      redirect_to admin_rooms_path(anchor: @place.slug), notice: [ "Đã lưu phòng #{@room.name}.", *price_notes, *capacity_notes ].join(" ")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @room.destroy
      redirect_to admin_rooms_path(anchor: @place.slug), notice: "Đã xoá phòng #{@room.name}."
    else
      redirect_to edit_admin_room_path(@room, anchor: "xoa-phong"), alert: @room.errors.full_messages.to_sentence
    end
  end

  # Staff too: cleaning is day-to-day work, not an owner-only room change. Also ends Bảo trì early.
  def clean
    was = @room.maintenance?
    @room.clean!
    redirect_back_or_to admin_place_path(@place.slug), notice: was ? "Xong bảo trì #{@room.name}, phòng sẵn sàng." : "Đã dọn xong #{@room.name}."
  end

  # Bảo trì (#121): staff too. Blocks the room through maintenance_until.
  def maintenance
    if @room.update(params.expect(room: [ :maintenance_reason, :maintenance_until ]).merge(housekeeping: "maintenance"))
      redirect_to admin_place_path(@place.slug, anchor: helpers.dom_id(@room)), notice: "#{@room.name} bảo trì đến #{@room.maintenance_until.strftime("%d/%m")}."
    else
      redirect_to admin_place_path(@place.slug, anchor: helpers.dom_id(@room)), alert: @room.errors.full_messages.to_sentence
    end
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
      params.expect(room: [ :name, :max_guests, :price, :weekend_price, :active, :state, :maintenance_reason, :maintenance_until,
        :floor, :room_type_id, :note, amenities: [] ])
    end

    def price_notes
      return [] unless @room.saved_change_to_price? || @room.saved_change_to_weekend_price?
      kept = @room.upcoming_bookings.count
      [ ("#{kept} đặt phòng sắp tới giữ giá cũ." if kept.positive?),
        ("Giá thứ 6, thứ 7 đang thấp hơn ngày thường, kiểm tra lại nếu không cố ý." if @room.weekend_price_below_price?) ].compact
    end

    # Lowering Số khách tối đa still saves; upcoming stays with more guests are named so the owner can fix them.
    def capacity_notes
      return [] unless @room.saved_change_to_max_guests?
      @room.upcoming_bookings.where(guests: (@room.max_guests + 1)..).order(:start_date).map do
        "Đặt phòng #{helpers.stay_dates(it)} có #{it.guests} khách, nhiều hơn tối đa #{@room.max_guests}."
      end
    end
end
