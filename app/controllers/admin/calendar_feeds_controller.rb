class Admin::CalendarFeedsController < Admin::BaseController
  before_action :set_feed, only: %i[sync destroy]

  # Every room's feeds by homestay; rooms with a failing feed first.
  def index
    rooms = Current.user.accessible_rooms.includes(:place, :calendar_feeds).sort_by do |room|
      [ room.place.name, room.calendar_feeds.any?(&:last_error) ? 0 : 1, room.name ]
    end
    @rooms_by_place = rooms.group_by(&:place)
  end

  # Syncs inline so the owner sees straight away whether the link works.
  def create
    @room = Current.user.accessible_rooms.find(params[:room_id])
    @calendar_feed = @room.calendar_feeds.build(params.expect(calendar_feed: [ :provider, :url ]))
    if @calendar_feed.save
      if @calendar_feed.sync
        redirect_to edit_admin_room_path(@room), notice: "Đã thêm và đồng bộ."
      else
        redirect_to edit_admin_room_path(@room), alert: "Đã thêm, nhưng đồng bộ lỗi: #{@calendar_feed.last_error}"
      end
    else
      @place = @room.place
      render "admin/rooms/edit", status: :unprocessable_entity
    end
  end

  def sync
    if @feed.synced_recently?
      redirect_to edit_admin_room_path(@feed.room), alert: "Vừa đồng bộ, thử lại sau 1 phút."
    elsif @feed.sync
      redirect_to edit_admin_room_path(@feed.room), notice: "Đã đồng bộ."
    else
      redirect_to edit_admin_room_path(@feed.room), alert: "Đồng bộ lỗi: #{@feed.last_error}"
    end
  end

  def destroy
    @feed.destroy!
    redirect_to edit_admin_room_path(@feed.room), notice: "Đã xoá kênh #{@feed.provider_label}."
  end

  private
    def set_feed
      @feed = Current.user.accessible_calendar_feeds.find(params[:id])
    end
end
