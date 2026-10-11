class CreateSyncRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :sync_runs do |t|
      t.references :calendar_feed, null: false, foreign_key: { on_delete: :cascade }
      t.string :trigger, null: false
      t.boolean :ok, null: false
      t.string :error
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :removed_count, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :finished_at, null: false
      t.index :started_at
      t.check_constraint "\"trigger\" IN ('hourly', 'manual', 'added')", name: "sync_runs_trigger_values"
    end
  end
end
