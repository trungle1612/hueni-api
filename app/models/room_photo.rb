require "image_processing/vips" # libvips only where photos are handled; booting (importmap audit) works without it

# Ảnh phòng (#187): public files hueni.me's nginx serves from /images/places/{slug}/rooms/{room-id}/{key}.webp.
# Only the resized WebP is written, metadata (EXIF, GPS) stripped. key is random per upload and never reused:
# nginx sends Cache-Control immutable. Saved through Room#photo_files=, which reports errors on the room as Ảnh phòng ….
class RoomPhoto < ApplicationRecord
  MAX = 10
  MAX_BYTES = 20.megabytes
  LONG_EDGE = 1600
  # libvips detects the format from the content, not the name or the browser's content type.
  LOADERS = %w[jpegload pngload webpload heifload].freeze

  belongs_to :room

  attr_accessor :file

  validate :file_is_a_photo, on: :create

  before_create do
    self.key = SecureRandom.hex(8)
    self.position = room.photos.maximum(:position).to_i + 1
  end
  after_create do
    path.dirname.mkpath
    FileUtils.install(webp.path, path, mode: 0o644)
  end
  after_destroy_commit { FileUtils.rm_f(path) }

  def self.root = Rails.configuration.x.photos_root
  def self.base_url = Rails.configuration.x.photos_url

  def url = "#{self.class.base_url}/#{relative_path}"

  def path = self.class.root.join(relative_path)

  private
    def relative_path = "places/#{room.place.slug}/rooms/#{room_id}/#{key}.webp"

    def file_is_a_photo
      return errors.add(:base, "không đọc được tệp ảnh") unless file.respond_to?(:path) && file.respond_to?(:size)
      return errors.add(:base, "quá lớn, mỗi ảnh tối đa #{MAX_BYTES / 1.megabyte} MB") if file.size > MAX_BYTES
      errors.add(:base, "chỉ nhận JPEG, PNG, WebP hoặc HEIC") unless LOADERS.include?(loader) && webp
    end

    def loader
      Vips::Image.new_from_file(file.path.to_s).get("vips-loader").delete_suffix("_source")
    rescue Vips::Error
      nil
    end

    # Auto-rotated by its EXIF orientation, then every metadata field dropped.
    def webp
      @webp ||= ImageProcessing::Vips.source(file.path.to_s).resize_to_limit(LONG_EDGE, LONG_EDGE)
        .convert("webp").saver(quality: 80, strip: true).call
    rescue Vips::Error
      nil
    end
end
