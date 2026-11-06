# Consent to Điều khoản + Chính sách bảo mật (#206, Decree 13/2023): the version the Mini App showed and when, the last one only.
class AddTermsConsent < ActiveRecord::Migration[8.1]
  def change
    %i[users registration_requests].each do |table|
      add_column table, :terms_version, :string
      add_column table, :terms_accepted_at, :datetime
    end
  end
end
