# A homestay's settings (#162). bank = Tài khoản chuyển khoản, shown when a guest pays by Chuyển khoản (staff too);
# commissions = the % each OTA keeps (Thực nhận), owners only.
class MiniApp::PlaceSerializer
  include Alba::Resource

  attributes :id, :slug, :name
  attribute(:role) { params[:role] }
  attribute(:bank) { { name: it.bank_name, account: it.bank_account, holder: it.bank_holder } if it.bank? }
  attributes :commissions, if: proc { params[:manage] }
  # Trang đặt phòng riêng (#172), owners only.
  attribute(:booking_site, if: proc { params[:manage] }) do
    { open: it.site_open, deposit_percent: it.site_deposit_percent, hidden_room_types: it.site_hidden_room_types,
      hold_minutes: it.site_hold_minutes, cutoff_hour: it.site_cutoff_hour, room_types: it.site_room_types }
  end
end
