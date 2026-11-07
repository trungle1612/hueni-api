namespace :invites do
  # Owner codes are admin-only (#211), e.g. for Zalo review: an owner code for the demo homestay, a few uses, 14 days.
  # bin/rails "invites:create[demo-homestay,owner,5,14]"
  desc "Create a mã mời: invites:create[slug,role,max_uses,days] (role owner|staff, default staff, 1 use, 7 days)"
  task :create, [ :slug, :role, :max_uses, :days ] => :environment do |_, args|
    admin = User.find_by!(role: "admin")
    invite = Place.find_by!(slug: args[:slug]).invites.create!(role: args[:role] || "staff", created_by: admin,
      max_uses: args[:max_uses] || 1, expires_at: (args[:days] || 7).to_i.days.from_now)
    puts "#{invite.display_code} · #{invite.role} · #{invite.max_uses} lần · hết hạn #{I18n.l(invite.expires_at, format: :short)}"
  end
end
