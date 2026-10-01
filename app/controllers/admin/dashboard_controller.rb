class Admin::DashboardController < Admin::BaseController
  def show
    @places = Current.user.accessible_places.order(:name)
  end
end
