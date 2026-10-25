# Mini App sign-in (#152): a random bearer token, shown once (`token` right after create) and stored as a SHA-256
# digest. Lasts LIFETIME from its last use. User#reset_login! and logout delete it.
class ApiToken < ApplicationRecord
  LIFETIME = 30.days

  belongs_to :user

  attr_reader :token

  before_validation on: :create do
    @token = SecureRandom.base58(32)
    self.token_digest = self.class.digest(@token)
    self.expires_at = LIFETIME.from_now
  end

  # The live token for this bearer string, renewed (at most hourly), or nil.
  def self.authenticate(token)
    return if token.blank?
    where(expires_at: Time.current..).find_by(token_digest: digest(token))&.tap(&:renew)
  end

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token)

  def renew
    update_columns(last_used_at: Time.current, expires_at: LIFETIME.from_now) unless last_used_at&.after?(1.hour.ago)
  end
end
