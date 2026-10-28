# Kênh OTA: a room with its feeds (none = Chưa có kênh), oldest first.
class MiniApp::RoomFeedsSerializer
  include Alba::Resource

  attributes :id, :name, :active
  many(:calendar_feeds, key: :feeds, resource: MiniApp::FeedSerializer) { |feeds| feeds.sort_by(&:created_at) }
end
