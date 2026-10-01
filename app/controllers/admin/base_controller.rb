# Parent of every /admin controller. Look records up only through Current.user.accessible_*
# (e.g. Current.user.accessible_rooms.find(params[:id])): out of scope → RecordNotFound → 404.
class Admin::BaseController < ApplicationController
end
