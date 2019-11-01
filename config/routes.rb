Rails.application.routes.draw do
  scope path: Rails.configuration.pompa.url do
    if Rails.configuration.pompa.endpoints.admin
      resources :events
      resources :victims, only: [:index, :show, :destroy]
      resources :scenarios
      resources :campaigns
      resources :attachments
      resources :resources
      resources :templates
      resources :goals
      resources :mailers
      resources :groups
      resources :targets
      resources :workers, only: [:index, :show]

      match '/targets/upload', via: [:post, :put], to: 'targets#upload'
      match '/targets/from-victims', via: [:post, :put], to: 'targets#from_victims'

      post '/groups/:id/clear', to: 'groups#clear'

      get '/scenarios/:id/report', to: 'scenario_reports#show'

      get '/scenarios/:id/victims-summary', to: 'scenarios#victims_summary'
      post '/scenarios/:id/synchronize-group', to: 'scenarios#synchronize_group'

      get '/victims/:id/report', to: 'victim_reports#show'

      get '/victims/:id/mail', to: 'victims#mail'

      post '/victims/:id/send-email', to: 'victims#send_email'
      post '/victims/:id/reset-state', to: 'victims#reset_state'

      post '/campaigns/:id/start', to: 'campaigns#start'
      post '/campaigns/:id/pause', to: 'campaigns#pause'
      post '/campaigns/:id/finish', to: 'campaigns#finish'

      get '/resources/:id/download', to: 'resources#download'
      match '/resources/:id/upload', via: [:post, :put], to: 'resources#upload'

      post '/templates/:id/duplicate', to: 'templates#duplicate'
      post '/templates/:id/export', to: 'templates#export'
      match '/templates/import', via: [:post, :put], to: 'templates#import'

      get '/events/series/:period', to: 'events#series'

      get '/workers/replies/:queue_id', to: 'workers#replies'
      get '/workers/files/:queue_id', to: 'workers#files'

      if Rails.configuration.pompa.authentication.enabled
        get '/auth', to: 'auth#index'
        get '/auth/metadata', to: 'auth#metadata'
        post '/auth/init', to: 'auth#init'
        post '/auth/callback', to: 'auth#callback'
        post '/auth/token', to: 'auth#token'
        post '/auth/refresh', to: 'auth#refresh'
        post '/auth/revoke', to: 'auth#revoke'
      end
    end

    if Rails.configuration.pompa.endpoints.public
      scope path: '/public' do
        match '/', via: :all, to: 'public#index'
        match '*path', via: :all, to: 'public#index'
      end
    end

    if Rails.configuration.pompa.endpoints.sidekiq_console
      require 'sidekiq/web'
      Sidekiq::Web.set :session_secret, Rails.application.secrets[:secret_key_base]
      mount Sidekiq::Web => '/sidekiq'
    end
  end
end
