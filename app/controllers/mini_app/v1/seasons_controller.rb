# Mùa và ngày lễ (#163), owners only: { season: { name, from, to, pct } }. Only nights booked from now on take a change.
class MiniApp::V1::SeasonsController < MiniApp::V1::BaseController
  def create
    @place = Current.user.accessible_places.find(params[:place_id])
    authorize!(:manage, @place)
    season = @place.seasons.build(season_params)
    season.save ? render(json: MiniApp::SeasonSerializer.new(season), status: :created) : render_invalid(season)
  end

  def update
    season = find_season
    season.update(season_params) ? render(json: MiniApp::SeasonSerializer.new(season)) : render_invalid(season)
  end

  def destroy
    find_season.destroy!
    head :no_content
  end

  private
    def find_season
      season = Season.where(place: Current.user.accessible_places).find(params[:id])
      authorize!(:manage, @place = season.place)
      season
    end

    def season_params = params.expect(season: %i[name from to pct])
end
