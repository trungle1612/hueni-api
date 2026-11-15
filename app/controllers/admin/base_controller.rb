# Parent of every /admin controller. /admin is the admins' area only (#85, #247): accounts, registrations, invites,
# announcements and sync runs. Owners and staff work in the PMS PWA, so they are sent there.
class Admin::BaseController < ApplicationController
  before_action :require_admin

  # A missing record: a friendly 404 inside the admin layout, also in development.
  rescue_from ActiveRecord::RecordNotFound, with: -> { render "admin/not_found", status: :not_found, formats: :html }

  private
    def require_admin
      redirect_to pms_today_path unless Current.user.admin?
    end
end
