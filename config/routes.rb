Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resource :registration, only: %i[new create]

  # OmniAuth callbacks (path_prefix /users/auth configurado en initializer)
  get "/users/auth/:provider/callback", to: "omniauth_callbacks#create"
  get "/users/auth/failure", to: "omniauth_callbacks#failure"

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  get "dashboard", to: "dashboard#show", as: :dashboard

  resources :tickets, only: %i[new create update] do
    collection do
      post :process_tickets, path: "process"
    end
    member do
      get :verify
      patch :requeue
    end
  end
end
