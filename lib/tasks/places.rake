namespace :places do
  desc "Import places from hueni's homestay.json (default: db/places/homestay.json, a local, git-ignored copy from hue-ni)"
  task :import, [ :path ] => :environment do |_, args|
    path = args[:path] || Rails.root.join("db/places/homestay.json")
    counts = Place.import(JSON.parse(File.read(path)).fetch("places"))
    puts counts.map { |k, v| "#{k} #{v}" }.join(", ")
  end
end
