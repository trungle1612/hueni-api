require "resolv"
require "net/http"

class CalendarFeed < ApplicationRecord
  MAX_BYTES = 2.megabytes
  MAX_REDIRECTS = 3
  TIMEOUT = 15

  belongs_to :room
  has_many :bookings, dependent: :delete_all

  after_commit { Vacancy.bust }

  enum :provider, { airbnb: "airbnb", booking: "booking", other: "other" }, validate: true

  validates :url, presence: true
  validate :url_is_public_http, if: -> { url.present? }

  def self.public_ip?(address)
    ip = IPAddr.new(address.to_s).native
    !(ip.private? || ip.loopback? || ip.link_local? || ip.to_i.zero?)
  rescue IPAddr::InvalidAddressError
    false
  end

  # SSRF guard: addresses of an http(s) URL's host, or [] unless every one is public.
  def self.public_addresses(uri)
    return [] unless uri.is_a?(URI::HTTP) && uri.hostname.present?
    addresses = Resolv.getaddresses(uri.hostname)
    addresses.all? { public_ip?(it) } ? addresses : []
  end

  # Replaces this feed's bookings with the feed's events. On any error no bookings change;
  # the error is recorded in last_error instead. Returns true on success.
  def sync
    events = parse(fetch)
    transaction do
      uids = events.map do |event|
        bookings.find_or_initialize_by(uid: event[:uid])
          .update!(room:, start_date: event[:start_date], end_date: event[:end_date], source: "ical", status: "confirmed")
        event[:uid]
      end
      bookings.where(end_date: Date.current.next_day..).where.not(uid: uids).delete_all
      update_columns(last_synced_at: Time.current, last_error: nil, last_error_at: nil)
    end
    Vacancy.bust
    true
  rescue StandardError => error
    update_columns(last_error: "#{error.class}: #{error.message}".truncate(500), last_error_at: Time.current)
    false
  end

  private
    def url_is_public_http
      errors.add(:url, :invalid) if self.class.public_addresses(URI.parse(url)).empty?
    rescue URI::InvalidURIError
      errors.add(:url, :invalid)
    end

    def fetch
      uri = URI.parse(url)
      (MAX_REDIRECTS + 1).times do
        location, body = get(uri)
        return body unless location
        uri = uri.merge(location)
      end
      raise "more than #{MAX_REDIRECTS} redirects"
    end

    # Connects to the already-checked IP so a second DNS lookup can't swap in a private address.
    def get(uri)
      address = self.class.public_addresses(uri).first or raise "URL must be http(s) on a public host"
      http = Net::HTTP.new(uri.hostname, uri.port, nil)
      http.ipaddr = address
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = http.read_timeout = http.write_timeout = TIMEOUT
      http.start do
        http.request_get(uri.request_uri) do |response|
          return [ response["location"].to_s, nil ] if response.is_a?(Net::HTTPRedirection)
          raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPOK)
          body = +""
          response.read_body do |chunk|
            body << chunk
            raise "response larger than 2 MB" if body.bytesize > MAX_BYTES
          end
          return [ nil, body ]
        end
      end
    end

    def parse(body)
      calendars = Icalendar::Calendar.parse(body)
      raise "not an iCalendar feed" if calendars.empty?
      calendars.flat_map(&:events).filter_map do |event|
        next if event.uid.blank? || event.dtstart.nil?
        start_date = hue_date(event.dtstart)
        end_date = event.dtend ? hue_date(event.dtend) : start_date.next_day
        next if end_date <= start_date || end_date < Date.current.yesterday
        { uid: event.uid.to_s, start_date:, end_date: }
      end
    end

    # All-day values are dates already; date-times become the Huế calendar date.
    def hue_date(value)
      value.respond_to?(:hour) ? value.in_time_zone.to_date : value.to_date
    end
end
