# Hiển thị trên hue-ni (#283, board HueniListing.dc.html, owners): the site_* settings of the current homestay, the
# Thông tin cần có checklist (Place#site_missing; the bank only with a Cọc), Giờ nhận, trả phòng (+ optional quy định), and a preview of hue-ni's card.
# Readiness and validation live in Place (#282); the frozen Mini App's PATCH booking_site edits the same columns.
class Pms::ListingsController < Pms::BaseController
  before_action -> { authorize!(:manage, current_place) if current_place }, only: :show
  before_action :set_place, only: %i[update rules]
  before_action -> { authorize!(:manage, @place) }, only: %i[update rules]

  SAVED = "Đã cập nhật. hue-ni hiển thị thay đổi trong vài phút."

  def show
  end

  # Rooms come as the shown ones; hidden = the active rooms left out, plus hidden rooms switched off now (#302).
  def update
    site = params.expect(listing: [ :open, :mode, :reply_minutes, :cutoff_hour, :deposit_percent, :hold_minutes, :show_phone, shown_room_ids: [] ])
    active = @place.rooms.where(active: true).ids
    hidden = (@place.site_hidden_room_ids.to_a - active) | (active - site.fetch(:shown_room_ids, []).map(&:to_i))
    if @place.update(site.except(:shown_room_ids).to_h.transform_keys { "site_#{it}" }.merge(site_hidden_room_ids: hidden))
      redirect_to pms_listing_path, status: :see_other, flash: { toast: SAVED }
    else
      render :show, status: :unprocessable_entity
    end
  end

  def rules
    if @place.update(params.expect(place: %i[check_in_time check_out_time house_rules]))
      redirect_to pms_listing_path, status: :see_other, flash: { toast: SAVED }
    else
      @rules_failed = true
      render :show, status: :unprocessable_entity
    end
  end

  private
    def set_place
      @place = current_place or raise ActiveRecord::RecordNotFound
    end
end
