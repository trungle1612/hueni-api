Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  get "dat-mat-khau/:token", to: "password_setups#edit", as: :password_setup
  patch "dat-mat-khau/:token", to: "password_setups#update"
  # POST /auth/zalo2 (the Zalo button) is OmniAuth middleware, not a route.
  get "auth/zalo2/callback", to: "zalo_sessions#create"
  get "auth/failure", to: "zalo_sessions#failure"
  # Owner self-registration, after a Zalo login that matched no account.
  get "dang-ky", to: "registrations#new", as: :registration
  post "dang-ky", to: "registrations#create"
  patch "dang-ky", to: "registrations#update"
  delete "dang-ky", to: "registrations#destroy"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA files from app/views/pwa/* (#228), linked from layouts/pms.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # PMS PWA for owners and staff (#227, ADR-002): the current homestay lives in the session, not the URL.
  scope module: :pms, as: :pms do
    get "hom-nay", to: "today#show", as: :today
    get "lich", to: "calendars#show", as: :calendar
    get "them", to: "more#show", as: :more
    delete "tai-khoan", to: "more#destroy", as: :account
    get "dieu-khoan", to: "legal#show", as: :legal
    get "bao-cao", to: "reports#show", as: :report
    get "tim", to: "searches#show", as: :search
    patch "co-so/:slug", to: "places#update", as: :place
    get "cai-dat", to: "settings#show", as: :settings
    patch "cai-dat/chuyen-khoan", to: "settings#bank", as: :settings_bank
    resources :services, path: "cai-dat/dich-vu", only: %i[create update destroy]
    resources :members, path: "nhan-vien", only: %i[index create update destroy] do
      post :lock, on: :member, path: "khoa"
      post :unlock, on: :member, path: "mo-khoa"
      post :setup_link, on: :member, path: "link-moi"
    end
    get "nhat-ky", to: "activities#show", as: :activity
    get "thong-bao", to: "notifications#show", as: :notifications
    post "thong-bao/doc-het", to: "notifications#read_all", as: :read_all_notifications
    post "thong-bao/hoan-tac", to: "notifications#undo_read", as: :undo_read_notifications
    patch "thong-bao/cai-dat", to: "notifications#settings", as: :notification_settings
    post "thong-bao/thiet-bi", to: "push_subscriptions#create", as: :push_subscription
    delete "thong-bao/thiet-bi", to: "push_subscriptions#destroy"
    get "thong-bao/:key", to: "notifications#open", as: :open_notification, constraints: { key: /[\w-]{1,40}/ }
    get "kenh", to: "channels#show", as: :channels
    post "kenh/dong-bo", to: "channels#sync", as: :channels_sync
    patch "kenh/hoa-hong", to: "channels#commissions", as: :channels_commissions
    resources :calendar_feeds, path: "kenh/lich", only: %i[create destroy] do
      post :sync, on: :member, path: "dong-bo"
    end
    resources :refund_requests, path: "hoan-tien", only: [] do
      post :approve, on: :member, path: "duyet"
      post :reject, on: :member, path: "tu-choi"
    end
    resources :bookings, path: "dat-phong", only: %i[new create show edit update], path_names: { new: "moi", edit: "sua" } do
      get :availability, on: :member, path: "lich-trong"
      get :saved, on: :member, path: "da-luu"
      get :rooms, on: :collection, path: "phong-trong"
      get :guest, on: :collection, path: "khach-cu"
      patch :discount, on: :member, path: "giam-gia"
      resources :payments, path: "thu-tien", only: %i[create destroy]
      resources :refund_requests, path: "yeu-cau-hoan-tien", only: :create
      resources :charges, path: "dich-vu", only: %i[create destroy]
    end
    resources :rooms, path: "phong", except: :show, path_names: { new: "moi", edit: "sua" } do
      patch :status, on: :member, path: "tinh-trang"
    end
    scope "dat-phong/:id", controller: :stays, as: :stay do
      post "nhan-phong", action: :check_in, as: :check_in
      post "tra-phong", action: :check_out, as: :check_out
      post "hoan-tac-nhan-phong", action: :undo_check_in, as: :undo_check_in
      post "hoan-tac-tra-phong", action: :undo_check_out, as: :undo_check_out
      post "doi-phong", action: :move, as: :move
      post "khai-bao", action: :declare, as: :declare
    end
  end
  root "sessions#new"

  # Old owner/staff /admin URLs (#247): bookmarks and links already sent open the matching PWA screen, on that homestay.
  pms = ->(path, keep = []) do
    redirect do |params, request|
      query = request.query_parameters.slice(*keep).merge("co_so" => params[:place_slug]).compact_blank
      [ path.gsub(/:(\w+)/) { params[$1.to_sym] }, query.to_query.presence ].compact.join("?")
    end
  end
  scope "admin" do
    get "calendar", to: pms.("/lich", %w[from])
    get "report", to: pms.("/bao-cao", %w[period month])
    get "tim", to: pms.("/tim", %w[q])
    get "places/:place_slug", to: pms.("/hom-nay")
    get "places/:place_slug/calendar", to: pms.("/lich", %w[from])
    get "places/:place_slug/activity", to: pms.("/nhat-ky")
    get "places/:place_slug/report", to: pms.("/bao-cao", %w[period month])
    get "places/:place_slug/bookings/new", to: pms.("/dat-phong/moi", %w[room_id start_date end_date])
    get "places/:place_slug/members(/*rest)", to: pms.("/nhan-vien")
    get "places/:place_slug/rooms/new", to: pms.("/phong/moi")
    get "rooms", to: pms.("/phong")
    get "rooms/:id/edit", to: pms.("/phong/:id/sua")
    get "calendar_feeds", to: pms.("/kenh")
    get "bookings/:id(/edit)", to: pms.("/dat-phong/:id"), constraints: { id: /\d+/ }
    get "bookings/:id/history", to: pms.("/dat-phong/:id"), constraints: { id: /\d+/ }
  end

  namespace :admin do
    root "dashboard#show"
    resources :sync_runs, only: :index, path: "dong-bo"
    resources :invites, only: %i[index create destroy], path: "ma-moi"
    resources :announcements, only: %i[index create edit update destroy], path: "thong-bao"
    resources :users, only: %i[index new create edit update] do
      post :reset_password, on: :member
    end
    resources :registration_requests, only: %i[show update] do
      member do
        patch :approve
        patch :reject
      end
    end
  end

  # Zalo Mini App API (#119 C).
  scope "api/v1", module: "mini_app/v1", as: "api_v1", defaults: { format: :json } do
    resource :session, only: %i[create destroy]
    post "zalo/webhook", to: "zalo_webhooks#create", as: :zalo_webhook
    resource :registration, only: %i[show create update]
    resource :me, only: %i[show destroy], controller: "me" do
      post :terms
      patch :notifications
    end
    resources :places, only: :show do
      member do
        get :rooms
        get :today
        get :board
        get :calendar
        get :availability
        get :services
        get :report
        post :search
        get :calendar_feeds
        get :activity
        get :members
        patch :commissions
        patch :bank
        patch :booking_site
        patch :rules
        get :seasons
        get :surcharges
        get :shift, to: "shifts#show"
        post "shift/close", to: "shifts#close", as: :close_shift
        post :cash_expenses, to: "shifts#create_expense"
        get :housekeeping, to: "cleanings#index"
        post :guests, to: "guests#index"
      end
      resources :bookings, only: :create
      resources :rooms, only: :create
      resources :services, only: :create
      resources :seasons, only: :create
      resources :surcharges, only: :create
      resources :groups, only: :create
      resources :memberships, only: %i[index create]
      resources :refund_requests, only: :index
      resources :notifications, only: :index do
        collection do
          post :read
          post :unread
        end
      end
    end
    resources :memberships, only: %i[update destroy] do
      member do
        post :lock
        post :unlock
        post :setup_link
      end
    end
    resources :refund_requests, only: [] do
      member do
        post :approve
        post :reject
      end
    end
    resources :groups, only: %i[show update] do
      member do
        post :check_in
        post :payments
      end
      resources :bookings, only: %i[create update], controller: "group_bookings"
    end
    resources :bookings, only: %i[show update] do
      member do
        post :check_in
        post :check_out
        post :no_show
        post :undo_check_in
        post :undo_check_out
        post :move
        post :declare
        patch :discount
        get :history
      end
      resources :payments, only: %i[create destroy]
      resources :charges, only: %i[create destroy]
      resources :refund_requests, only: :create
      resource :guest, only: %i[show update]
    end
    resources :rooms, only: %i[update destroy] do
      member do
        post :clean
        patch :maintenance
        patch :damage, to: "cleanings#damage"
      end
      resource :cleaning, only: :update do
        post :finish
        post :undo
      end
    end
    resources :services, only: %i[update destroy]
    resources :seasons, only: %i[update destroy]
    resources :surcharges, only: %i[update destroy]
    patch "cash_expenses/:id", to: "shifts#update_expense", as: :cash_expense
    delete "cash_expenses/:id", to: "shifts#destroy_expense"
    resources :calendar_feeds, only: [] do
      post :sync, on: :member
    end
    match "*path", to: "base#preflight", via: :options
  end

  namespace :v1 do
    get "vacancy", to: "vacancy#show"
    get "places/:slug/booking_site", to: "booking_site#show", as: :booking_site
    post "places/:slug/bookings", to: "booking_site#create", as: :booking_site_bookings
    get "bookings/:token", to: "booking_site#status", as: :booking_site_status
    match "*path", to: "base#preflight", via: :options
  end
end
