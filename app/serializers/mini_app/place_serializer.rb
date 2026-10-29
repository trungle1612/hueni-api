# A homestay's settings (#162). bank = Tài khoản chuyển khoản, shown when a guest pays by Chuyển khoản (staff too);
# commissions = the % each OTA keeps (Thực nhận), owners only.
class MiniApp::PlaceSerializer
  include Alba::Resource

  attributes :id, :slug, :name
  attribute(:role) { params[:role] }
  attribute(:bank) { { name: it.bank_name, account: it.bank_account, holder: it.bank_holder } if it.bank? }
  attributes :commissions, if: proc { params[:manage] }
end
