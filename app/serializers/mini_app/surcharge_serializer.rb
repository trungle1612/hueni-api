# A Phụ thu theo khách row (#163); price 0 = Miễn phí.
class MiniApp::SurchargeSerializer
  include Alba::Resource

  attributes :id, :name, :price, :unit
end
