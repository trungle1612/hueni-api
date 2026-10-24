# Kênh OTA (#125): Agoda as a provider, and each homestay's commission % per OTA.
class AddAgodaAndCommissions < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :calendar_feeds, name: "calendar_feeds_provider_values"
    add_check_constraint :calendar_feeds, "provider IN ('airbnb', 'booking', 'agoda', 'other')", name: "calendar_feeds_provider_values"
    add_column :places, :commissions, :json, null: false, default: {}
  end

  def down
    remove_column :places, :commissions
    execute "UPDATE calendar_feeds SET provider = 'other' WHERE provider = 'agoda'"
    remove_check_constraint :calendar_feeds, name: "calendar_feeds_provider_values"
    add_check_constraint :calendar_feeds, "provider IN ('airbnb', 'booking', 'other')", name: "calendar_feeds_provider_values"
  end
end
