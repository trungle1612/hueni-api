class Place < ApplicationRecord
  has_many :rooms
  has_many :place_memberships, dependent: :destroy
  has_many :users, through: :place_memberships

  after_commit { Vacancy.bust }

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  # Hoa hồng % per OTA (#125), set by the owner on Kênh OTA; a blank field removes it. For Thực nhận in Báo cáo later.
  COMMISSION_PROVIDERS = %w[airbnb booking agoda].freeze
  validate do
    errors.add(:commissions, "phải là số từ 0 đến 100") unless commissions.values.all? { it.is_a?(Numeric) && it.between?(0, 100) }
  end

  # "15,5" → 15.5; anything not a number is kept so the validation names it.
  def commissions=(value)
    value = value.to_h.stringify_keys.slice(*COMMISSION_PROVIDERS).transform_values { it.to_s.strip.tr(",", ".").presence }.compact
    super(value.transform_values { Float(it, exception: false) || it })
  end

  # Booking codes (#124): one UPDATE, so two bookings saved at once never share a number.
  def next_booking_number!
    Place.where(id:).update_all("last_booking_number = last_booking_number + 1")
    Place.where(id:).pick(:last_booking_number)
  end

  # Upserts places from hueni's homestay.json "places" array, keyed by slug. Never deletes.
  def self.import(hueni_places)
    counts = { created: 0, updated: 0, unchanged: 0 }
    transaction do
      hueni_places.each do |hp|
        place = find_or_initialize_by(slug: hp.fetch("id"))
        place.assign_attributes(
          name: hp.fetch("name"),
          address: hp["address"],
          phone: hp["phone"],
          rating: hp["rating"],
          lat: hp.dig("coordinates", "lat"),
          lng: hp.dig("coordinates", "lng"),
          website: hp["website"],
          cover_image_url: hp["coverImage"],
          google_place_id: hp["place_id"]
        )
        counts[place.new_record? ? :created : place.changed? ? :updated : :unchanged] += 1
        place.save!
      end
    end
    counts
  end
end
