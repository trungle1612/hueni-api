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

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  namespace :admin do
    root "dashboard#show"
    get "calendar", to: "calendars#index"
    get "report", to: "reports#index"
    get "tim", to: "searches#show", as: :search
    resources :places, only: :show, param: :slug do
      post :sync_feeds, on: :member
      patch :commissions, on: :member
      patch :bank, on: :member
      resources :services, only: %i[create update destroy]
      resource :calendar, only: :show
      resource :activity, only: :show
      resource :report, only: :show
      resources :rooms, only: %i[new create]
      resources :bookings, only: %i[new create] do
        get :availability, on: :collection
      end
      resources :members, only: %i[new create edit update destroy] do
        post :setup_link, on: :member
      end
    end
    resources :rooms, only: %i[index edit update destroy] do
      post :clean, on: :member
      patch :maintenance, on: :member
      resources :calendar_feeds, only: :create
    end
    resources :sync_runs, only: :index, path: "dong-bo"
    resources :users, only: %i[index new create edit update] do
      post :reset_password, on: :member
    end
    resources :registration_requests, only: %i[show update] do
      member do
        patch :approve
        patch :reject
      end
    end
    resources :calendar_feeds, only: %i[index destroy] do
      post :sync, on: :member
    end
    resources :bookings, only: %i[edit update] do
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
      resources :charges, controller: "booking_charges", only: %i[create destroy]
    end
  end

  # Zalo Mini App API (#119 C).
  scope "api/v1", module: "mini_app/v1", as: "api_v1", defaults: { format: :json } do
    resource :session, only: %i[create destroy]
    resource :registration, only: %i[show create update]
    resource :me, only: :show, controller: "me"
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
        get :shift, to: "shifts#show"
        post "shift/close", to: "shifts#close", as: :close_shift
        post :cash_expenses, to: "shifts#create_expense"
        get :housekeeping, to: "cleanings#index"
        post :guests, to: "guests#index"
      end
      resources :bookings, only: :create
      resources :rooms, only: :create
      resources :services, only: :create
      resources :groups, only: :create
      resources :memberships, only: %i[index create]
      resources :refund_requests, only: :index
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
    patch "cash_expenses/:id", to: "shifts#update_expense", as: :cash_expense
    delete "cash_expenses/:id", to: "shifts#destroy_expense"
    resources :calendar_feeds, only: [] do
      post :sync, on: :member
    end
    match "*path", to: "base#preflight", via: :options
  end

  namespace :v1 do
    get "vacancy", to: "vacancy#show"
  end
end
