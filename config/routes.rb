Rails.application.routes.draw do
  resources :books
  resources :orders, only: %i[index show new create] do
    member do
      patch :advance
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "books#index"
end
