# Phụ thu theo khách (#163), owners only: { surcharge: { name, price, unit } }. Listing it (GET /places/:id/surcharges) is staff too.
class MiniApp::V1::SurchargesController < MiniApp::V1::BaseController
  def create
    @place = Current.user.accessible_places.find(params[:place_id])
    authorize!(:manage, @place)
    surcharge = @place.surcharges.build(surcharge_params)
    surcharge.save ? render(json: MiniApp::SurchargeSerializer.new(surcharge), status: :created) : render_invalid(surcharge)
  end

  def update
    surcharge = find_surcharge
    surcharge.update(surcharge_params) ? render(json: MiniApp::SurchargeSerializer.new(surcharge)) : render_invalid(surcharge)
  end

  def destroy
    find_surcharge.destroy!
    head :no_content
  end

  private
    def find_surcharge
      surcharge = Surcharge.where(place: Current.user.accessible_places).find(params[:id])
      authorize!(:manage, @place = surcharge.place)
      surcharge
    end

    def surcharge_params = params.expect(surcharge: %i[name price unit])
end
