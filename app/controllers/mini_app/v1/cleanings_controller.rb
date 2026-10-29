# Buồng phòng (#166): owners and staff. The list is per homestay; each action is on one room and answers with its row.
class MiniApp::V1::CleaningsController < MiniApp::V1::BaseController
  Row = Data.define(:room, :kind, :urgent, :task)

  before_action :set_place, only: :index
  before_action :set_room, except: :index
  before_action -> { authorize!(:operate, @place) }

  # Dọn sau trả phòng: dirty rooms, plus those finished today (for Hoàn tác); Dọn hằng ngày: rooms with a guest in.
  # Urgent first, then by room name. checklist = the labels of a task's checks.
  def index
    rooms = @place.rooms.where(active: true).order(:name).to_a
    tasks = CleaningTask.today.where(room: rooms).includes(:assignee).order(:id).group_by(&:room_id)
    in_house = Booking.in_house.where(room: rooms).pluck(:room_id)
    arriving = Booking.blocking.not_checked_in.where(room: rooms, start_date: Booking.arrival_date..Date.current).pluck(:room_id)
    rows = rooms.filter_map do |room|
      task = tasks[room.id]&.then { |list| list.find { !it.done_at } || list.last }
      if room.dirty? || task&.done_at then Row.new(room:, kind: "checkout", urgent: arriving.include?(room.id), task:)
      elsif in_house.include?(room.id) then Row.new(room:, kind: "daily", urgent: false, task: nil)
      end
    end
    rows = rows.sort_by { [ it.urgent ? 0 : 1, it.kind == "checkout" ? 0 : 1, it.room.name ] }
    render json: { date: Date.current, checklist: CleaningTask::CHECKLIST, rows: MiniApp::CleaningSerializer.new(rows) }
  end

  # Người làm, ticks, Bắt đầu: { cleaning: { assignee_id, checks: [5 booleans], start: true } }.
  def update
    attrs = params.expect(cleaning: [ :assignee_id, :start, checks: [] ])
    changes = { assignee_id: attrs[:assignee_id], checks: attrs[:checks]&.map { ActiveModel::Type::Boolean.new.cast(it) }, start: ActiveModel::Type::Boolean.new.cast(attrs[:start]) }
    respond(@task = CleaningTask.for(@room)) { @task.change(**changes.compact) }
  end

  def finish = respond(@task = CleaningTask.for(@room)) { @task.finish }

  def undo = respond(@task = @room.cleaning_tasks.today.where.not(done_at: nil).order(:done_at).last || raise(ActiveRecord::RecordNotFound)) { @task.undo }

  # Báo hỏng hoặc thiếu đồ: { room: { damage_note } }, blank clears it.
  def damage
    @room.update(params.expect(room: [ :damage_note ])) ? render_row(CleaningTask.for(@room)) : render_invalid(@room)
  end

  private
    def set_place
      @place = Current.user.accessible_places.find(params[:id])
    end

    def set_room
      @room = Current.user.accessible_rooms.find(params[:room_id] || params[:id])
      @place = @room.place
    end

    def respond(task) = yield ? render_row(task) : render_invalid(task)

    def render_row(task)
      @room.reload
      task = nil if task.new_record?
      urgent = Booking.blocking.not_checked_in.where(room: @room, start_date: Booking.arrival_date..Date.current).exists?
      render json: MiniApp::CleaningSerializer.new(Row.new(room: @room, kind: @room.dirty? || task&.done_at ? "checkout" : "daily", urgent:, task:))
    end
end
