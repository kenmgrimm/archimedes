Rails.application.routes.draw do
  resources :contents do
    member do
      post :analyze
    end
  end
  
  # Entity routes with verification and merge functionality
  resources :entities do
    member do
      post :merge
    end
    
    collection do
      post :verify
      get :merge_form
    end
  end
  
  # Search routes for vector similarity search
  get 'search', to: 'search#index'
  
  get 'home/index'
  devise_for :users
  # Visualization routes
  get 'visualizations/knowledge_graph', to: 'visualizations#knowledge_graph', as: 'visualization_knowledge_graph'
  get 'visualizations/connection_stats', to: 'visualizations#connection_stats', as: 'visualization_connection_stats'
  
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "home#index"
end
