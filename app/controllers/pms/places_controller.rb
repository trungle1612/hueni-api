# Đổi cơ sở: only among the user's own homestays (404 otherwise).
class Pms::PlacesController < Pms::BaseController
  def update
    session[:pms_place] = places.find_by!(slug: params[:slug]).slug
    redirect_to pms_today_path, status: :see_other
  end
end
