namespace :invites do
  # Codes are admin-only (#211), like menu Mã mời. For Zalo review use invites:demo below, never a real homestay.
  # bin/rails "invites:create[slug,staff,1,7]"
  desc "Create a mã mời: invites:create[slug,role,max_uses,days] (role owner|staff, default staff, 1 use, 7 days)"
  task :create, [ :slug, :role, :max_uses, :days ] => :environment do |_, args|
    admin = User.find_by!(role: "admin")
    invite = Place.find_by!(slug: args[:slug]).invites.create!(role: args[:role] || "staff", created_by: admin,
      max_uses: args[:max_uses] || 1, expires_at: (args[:days] || 7).to_i.days.from_now)
    puts "#{invite.display_code} · #{invite.role} · #{invite.max_uses} lần · hết hạn #{I18n.l(invite.expires_at, format: :short)}"
  end

  # Zalo review (#211): a made-up homestay, never a real one, and an owner code for it. The homestay, its rooms and
  # bookings are created once (re-runs keep what the reviewer did); every run prints a new code.
  # bin/rails "invites:demo[5,14]"
  desc "Create the made-up Homestay Demo (once) and an owner mã mời for it: invites:demo[max_uses,days] (default 5 uses, 14 days)"
  task :demo, [ :max_uses, :days ] => :environment do |_, args|
    place = Place.find_by(slug: "demo-hueni") || Place.transaction do
      place = Place.create!(slug: "demo-hueni", name: "Homestay Demo", address: "Dữ liệu mẫu, không phải homestay thật")
      rooms = [ [ "101", "double", 2, 350_000 ], [ "102", "double", 2, 350_000 ], [ "201", "family", 4, 600_000 ], [ "202", "single", 1, 250_000 ] ]
        .map { |name, room_type, max_guests, price| place.rooms.create!(name:, room_type:, max_guests:, price:, active: true) }
      today = Date.current
      rooms[0].bookings.create!(start_date: today - 1, end_date: today + 1, guests: 2, guest_name: "Anh Minh (mẫu)", guest_phone: "0900000111", checked_in_at: 1.day.ago)
      rooms[1].bookings.create!(start_date: today, end_date: today + 2, guests: 2, guest_name: "Chị Mai (mẫu)", guest_phone: "0900000222")
        .payments.create!(amount: 200_000, payment_method: "cash", kind: "payment")
      past = rooms[2].bookings.create!(start_date: today - 5, end_date: today - 3, guests: 3, guest_name: "Gia đình Tuấn (mẫu)", guest_phone: "0900000333",
        checked_in_at: 5.days.ago, checked_out_at: 3.days.ago)
      past.payments.create!(amount: past.due, payment_method: "bank", kind: "payment")
      rooms[3].bookings.create!(start_date: today + 7, end_date: today + 9, guests: 1, guest_name: "Chị Thảo (mẫu)", guest_phone: "0900000444")
      place
    end
    invite = place.invites.create!(role: "owner", created_by: User.find_by!(role: "admin"), max_uses: args[:max_uses] || 5,
      expires_at: (args[:days] || 14).to_i.days.from_now)
    puts "#{place.name} (#{place.slug}): #{invite.display_code} · owner · #{invite.max_uses} lần · hết hạn #{I18n.l(invite.expires_at, format: :short)}"
  end
end
