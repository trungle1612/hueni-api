# The Mini App's Feed: an OTA calendar link of a room. Only the host is ever shown: the full URL carries the OTA's token.
# error = gone | parse | fetch (null when the last sync worked), error_message = what to do, in Vietnamese.
class MiniApp::FeedSerializer
  include Alba::Resource

  attributes :id, :room_id, :provider, :last_synced_at, :last_error_at
  attribute(:label) { it.provider_label }
  attribute(:host) { it.url_host }
  attribute(:error) { it.error_kind }
  attributes :error_message
end
