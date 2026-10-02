Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
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
    resources :places, only: :show, param: :slug do
      resource :calendar, only: :show
      resources :rooms, only: %i[new create]
      resources :bookings, only: %i[new create]
    end
    resources :rooms, only: %i[edit update] do
      resources :calendar_feeds, only: :create
    end
    resources :calendar_feeds, only: %i[index destroy] do
      post :sync, on: :member
    end
    resources :bookings, only: %i[edit update]
  end

  root to: redirect("/admin")

  namespace :v1 do
    get "vacancy", to: "vacancy#show"
  end
end
