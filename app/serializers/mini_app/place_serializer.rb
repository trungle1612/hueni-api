# A homestay's settings (#162). bank = Tài khoản chuyển khoản, shown when a guest pays by Chuyển khoản (staff too);
# commissions = the % each OTA keeps (Thực nhận), owners only. long_stay / cancel_policy (#163): Ở dài ngày and Chính sách huỷ.
class MiniApp::PlaceSerializer
  include Alba::Resource

  attributes :id, :slug, :name
  attribute(:role) { params[:role] }
  attribute(:bank) { { name: it.bank_name, account: it.bank_account, holder: it.bank_holder } if it.bank? }
  attributes :long_stay
  attribute(:cancel_policy) { { key: it.cancel_policy, label: Place::CANCEL_POLICIES[it.cancel_policy][0], text: Place::CANCEL_POLICIES[it.cancel_policy][1] } }
  attributes :commissions, if: proc { params[:manage] }
end
