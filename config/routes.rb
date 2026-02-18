Rails.application.routes.draw do
  resource :session, only: [:new, :create, :destroy]
  resource :registration, only: [:new, :create]

  # OmniAuth callbacks (path_prefix /users/auth configurado en initializer)
  get "/users/auth/:provider/callback", to: "omniauth_callbacks#create"
  get "/users/auth/failure", to: "omniauth_callbacks#failure"

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  get "dashboard", to: "dashboard#show", as: :dashboard
end
