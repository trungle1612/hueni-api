class AddZaloIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :zalo_id, :string
    add_index :users, :zalo_id, unique: true
  end
end
