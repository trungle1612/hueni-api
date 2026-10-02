class ChangeUserRolesToAdminAndUser < ActiveRecord::Migration[8.1]
  # Rights now come from place_memberships.role; the account role only says admin or not.
  def up
    remove_check_constraint :users, name: "users_role_values"
    execute "UPDATE users SET role = 'user' WHERE role = 'owner'"
    change_column_default :users, :role, from: "owner", to: "user"
    add_check_constraint :users, "role IN ('admin', 'user')", name: "users_role_values"
  end

  def down
    remove_check_constraint :users, name: "users_role_values"
    execute "UPDATE users SET role = 'owner' WHERE role = 'user'"
    change_column_default :users, :role, from: "user", to: "owner"
    add_check_constraint :users, "role IN ('admin', 'owner')", name: "users_role_values"
  end
end
