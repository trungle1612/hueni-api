# Thông báo hệ thống (#213), admins only (like Mã mời): Tính năng mới and Bảo trì for every Mini App user's Thông báo.
class Admin::AnnouncementsController < Admin::BaseController
  before_action :require_admin
  before_action :set_announcement, only: %i[edit update destroy]

  def index
    @announcements = Announcement.order(published_at: :desc)
    @announcement = Announcement.new(published_at: Time.current)
  end

  def create
    @announcement = Announcement.new(announcement_params)
    if @announcement.save
      redirect_to admin_announcements_path, notice: "Đã đăng thông báo."
    else
      @announcements = Announcement.order(published_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @announcement.update(announcement_params)
      redirect_to admin_announcements_path, notice: "Đã lưu thông báo."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @announcement.destroy!
    redirect_to admin_announcements_path, notice: "Đã xoá thông báo."
  end

  private
    def set_announcement = @announcement = Announcement.find(params[:id])

    def announcement_params = params.expect(announcement: %i[kind title summary intro content note cta cta_path published_at])
end
