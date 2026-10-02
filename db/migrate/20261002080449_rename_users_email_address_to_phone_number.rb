class RenameUsersEmailAddressToPhoneNumber < ActiveRecord::Migration[8.1]
  # Owners log in with their phone number (Zalo later), not email. Nothing is deployed yet, so no data to convert.
  def change
    rename_column :users, :email_address, :phone_number
  end
end
