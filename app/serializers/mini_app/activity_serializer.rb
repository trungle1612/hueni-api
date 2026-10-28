# One line of Hoạt động / Lịch sử (Activity::Line): the same Vietnamese wording as /admin.
# kind: check_in, check_out, clean, booking, cancel, edit, sync, room, feed, error, ok, stay (hold: old Giữ chỗ history).
class MiniApp::ActivitySerializer
  include Alba::Resource

  attributes :id, :at, :kind, :action, :detail, :actor, :room_id, :room_name
end
