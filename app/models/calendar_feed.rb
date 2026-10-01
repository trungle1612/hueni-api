require "resolv"

class CalendarFeed < ApplicationRecord
  belongs_to :room
  has_many :bookings, dependent: :delete_all

  after_commit { Vacancy.bust }

  enum :provider, { airbnb: "airbnb", booking: "booking", other: "other" }, validate: true

  validates :url, presence: true
  validate :url_is_public_http, if: -> { url.present? }

  # SSRF guard, also used at fetch time (#14).
  def self.public_ip?(address)
    ip = IPAddr.new(address.to_s).native
    !(ip.private? || ip.loopback? || ip.link_local? || ip.to_i.zero?)
  rescue IPAddr::InvalidAddressError
    false
  end

  private
    def url_is_public_http
      uri = URI.parse(url)
      addresses = uri.is_a?(URI::HTTP) && uri.hostname.present? ? Resolv.getaddresses(uri.hostname) : []
      errors.add(:url, :invalid) unless addresses.any? && addresses.all? { self.class.public_ip?(it) }
    rescue URI::InvalidURIError
      errors.add(:url, :invalid)
    end
end
