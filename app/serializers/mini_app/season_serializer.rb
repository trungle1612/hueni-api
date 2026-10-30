# A season (#163): + pct on the nights from `from` to `to`, both included.
class MiniApp::SeasonSerializer
  include Alba::Resource

  attributes :id, :name, :from, :to, :pct
end
