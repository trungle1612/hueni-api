class ApplicationController < ActionController::Base
  include Authentication
  # After require_authentication, so Current.user is set.
  before_action :set_paper_trail_whodunnit
  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private
    def user_for_paper_trail = Current.user&.id
end
