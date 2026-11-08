# Thông báo hệ thống (#213): Tính năng mới or Bảo trì, written by admins in /admin, shown to every Mini App user
# for Notification::DAYS from published_at. content: "## Heading" starts a block, "- item" / "1. item" are its list.
class Announcement < ApplicationRecord
  KINDS = { "feature" => "Tính năng mới", "maintenance" => "Bảo trì" }.freeze

  validates :kind, inclusion: { in: KINDS.keys }
  validates :title, :summary, :published_at, presence: true
  validates :title, :summary, :cta, length: { maximum: 120 }
  validates :cta_path, format: { with: %r{\A/[\w/\-?=&]*\z}, message: "phải là đường dẫn trong Mini App, bắt đầu bằng /" }, allow_blank: true
  validates :cta_path, presence: { message: "cần có khi có nút" }, if: -> { cta.present? }

  scope :shown, -> { where(published_at: Notification::DAYS.days.ago..Time.current) }

  def kicker = kind == "feature" ? "TÍNH NĂNG MỚI · #{published_at.strftime("%d/%m/%Y")}" : "BẢO TRÌ HỆ THỐNG"

  # [{ h:, ordered:, items: [] }]; lines before the first heading go in a block without one.
  def blocks
    content.to_s.lines.map(&:strip).compact_blank.each_with_object([]) do |line, blocks|
      next blocks << { h: line.delete_prefix("## "), ordered: false, items: [] } if line.start_with?("## ")
      blocks << { h: nil, ordered: false, items: [] } if blocks.empty?
      blocks.last[:ordered] = true if line.match?(/\A\d+\.\s/)
      blocks.last[:items] << line.sub(/\A(-|\d+\.)\s*/, "")
    end
  end

  def detail = { kind:, kicker:, title:, intro: intro.presence, blocks:, note: note.presence, cta: cta.presence, cta_path: cta_path.presence }
end
