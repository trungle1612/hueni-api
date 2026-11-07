# Xoá tài khoản (#192): the row stays, anonymised, so payments, shifts and Hoạt động still name "Người dùng đã xoá".
class AddDeletedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deleted_at, :datetime
    change_column_null :users, :phone_number, true
  end
end
