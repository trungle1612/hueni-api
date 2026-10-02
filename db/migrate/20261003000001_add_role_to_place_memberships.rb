class AddRoleToPlaceMemberships < ActiveRecord::Migration[8.1]
  # Existing members become owners: until now every member could manage their homestay.
  def change
    add_column :place_memberships, :role, :string, null: false, default: "owner"
    add_check_constraint :place_memberships, "role IN ('owner', 'staff')", name: "place_memberships_role_values"
  end
end
