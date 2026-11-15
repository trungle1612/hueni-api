# Thông báo trên điện thoại này (#237): push_controller.js sends the browser's subscription after the tap that allowed
# notifications (and again on each page, so a new login on the same phone takes it over), and removes it on turning off.
class Pms::PushSubscriptionsController < Pms::BaseController
  def create
    keys = params[:keys].is_a?(ActionController::Parameters) ? params[:keys] : {}
    subscription = PushSubscription.save_for(Current.session, endpoint: params[:endpoint], p256dh: keys[:p256dh], auth: keys[:auth])
    head(subscription.persisted? && subscription.errors.empty? ? :no_content : :unprocessable_content)
  end

  def destroy
    Current.user.push_subscriptions.find_by!(endpoint: params[:endpoint].to_s).destroy
    head :no_content
  end
end
