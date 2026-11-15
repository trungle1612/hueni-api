namespace :push do
  desc "Print a new VAPID key for Web Push (#237): set it as env VAPID_KEY (Actions secret)"
  task :key do
    require "openssl"
    require "base64"
    puts Base64.strict_encode64(OpenSSL::PKey::EC.generate("prime256v1").to_der)
  end
end
