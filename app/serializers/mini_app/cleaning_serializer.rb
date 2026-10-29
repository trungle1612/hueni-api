# One row of Buồng phòng (#166): a room to clean today. kind checkout = left dirty (has a task), daily = guest in
# (no task). urgent = a guest arrives today. task = today's task, null until someone touches it.
class MiniApp::CleaningSerializer
  include Alba::Resource

  attributes :kind, :urgent
  attribute(:room_id) { it.room.id }
  attribute(:room_name) { it.room.name }
  attribute(:damage_note) { it.room.damage_note }
  attribute(:task) do |row|
    row.task&.then { { id: it.id, assignee_id: it.assignee_id, assignee_name: it.assignee&.name, checks: it.checks, started_at: it.started_at, done_at: it.done_at } }
  end
end
