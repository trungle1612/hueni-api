# Buồng phòng (#166): today's cleaning of a room left dirty (check-out, room move, end of Bảo trì): who, the fixed
# checklist (CleaningTask::CHECKLIST), started / done. Daily tidies of occupied rooms keep no row. damage_note on the
# room: Báo hỏng hoặc thiếu đồ, blocks nothing (Bảo trì does).
class CreateCleaningTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :cleaning_tasks do |t|
      t.references :room, null: false, foreign_key: true
      t.date :date, null: false
      t.references :assignee, foreign_key: { to_table: :users }
      t.json :checks, null: false, default: []
      t.datetime :started_at
      t.datetime :done_at
      t.timestamps
    end
    add_index :cleaning_tasks, [ :room_id, :date ]

    add_column :rooms, :damage_note, :string
  end
end
