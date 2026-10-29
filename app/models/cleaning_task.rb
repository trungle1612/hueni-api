# Buồng phòng (#166): cleaning a dirty room today. Finishing needs a person and every checklist item, and marks
# the room clean like Dọn xong (logged there); Hoàn tác the same day makes it dirty again.
class CleaningTask < ApplicationRecord
  CHECKLIST = [
    "Thay ga, vỏ gối, khăn tắm",
    "Lau phòng tắm, bồn cầu",
    "Hút bụi, lau sàn",
    "Bổ sung nước suối, giấy, xà phòng",
    "Kiểm tra đồ để quên, đồ hỏng"
  ].freeze

  belongs_to :room
  belongs_to :assignee, class_name: "User", optional: true

  attribute :checks, :json, default: -> { CHECKLIST.map { false } }
  validate -> { errors.add(:checks, "phải có #{CHECKLIST.size} mục đúng / sai") unless checks.is_a?(Array) && checks.size == CHECKLIST.size && checks.all? { it.in?([ true, false ]) } }
  validate -> { errors.add(:assignee, "phải là thành viên của homestay") unless room.place.users.exists?(assignee_id) }, if: -> { assignee_id && will_save_change_to_assignee_id? }

  scope :today, -> { where(date: Date.current) }

  # Today's task for the room: the open one, else a new one. An open task from an earlier day is left behind.
  def self.for(room) = room.cleaning_tasks.today.find_by(done_at: nil) || room.cleaning_tasks.build(date: Date.current)

  # Người làm, ticks and Bắt đầu, only while the room waits for cleaning.
  def change(assignee_id: self.assignee_id, checks: self.checks, start: false)
    return refuse("Phòng không cần dọn") unless room.dirty?
    self.assignee_id, self.checks = assignee_id, checks
    self.started_at ||= Time.current if start
    save
  end

  # Xong, phòng sẵn sàng.
  def finish
    if !room.dirty? then refuse("Phòng không cần dọn")
    elsif !assignee then refuse("Chọn người dọn trước")
    elsif !checks.all? then refuse("Đánh dấu đủ #{CHECKLIST.size} việc trước khi xong")
    else
      transaction do
        update!(done_at: Time.current, started_at: started_at || Time.current)
        room.clean!
      end
    end
  end

  # Hoàn tác the same day, while nothing else changed the room.
  def undo
    if !done_at || done_at.to_date != Date.current then refuse("Chỉ hoàn tác được trong ngày dọn")
    elsif !room.clean? then refuse("Phòng đã đổi tình trạng, không hoàn tác được")
    else
      transaction do
        update!(done_at: nil)
        room.dirty!
      end
    end
  end

  private
    def refuse(reason)
      errors.add(:base, reason)
      false
    end
end
