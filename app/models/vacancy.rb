# Free rooms per place on a Huế calendar day: { "place-slug" => { left:, max_guests: } }.
# Places with no active rooms are omitted.
module Vacancy
  # Today's vacancy for the public API. Busted by Place/Room/Booking commits; bulk writes must call bust.
  def self.cached
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) { { date: Date.current, places: on } }
  end

  def self.bust
    Rails.cache.delete(cache_key)
  end

  def self.cache_key = [ "vacancy", Date.current ]

  def self.on(date = Date.current)
    busy = Booking.blocking_on(date).pluck(:room_id).to_set
    Room.where(active: true).joins(:place).pluck("places.slug", :id, :max_guests)
      .group_by(&:first)
      .transform_values do |rooms|
        free = rooms.reject { |_, id, _| busy.include?(id) }
        { left: free.size, max_guests: free.map(&:last).max || 0 }
      end
  end
end
