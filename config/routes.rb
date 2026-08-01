Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "documents#index"
  resources :documents, only: [ :index, :create, :show ] do
    resources :questions, only: [ :create ]
  end
end
