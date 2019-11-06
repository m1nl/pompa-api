# frozen_string_literal: true

source 'https://rubygems.org'

gem 'rails', '~> 6.0.1'

gem 'pg'
gem 'redis'

gem 'concurrent-ruby-ext'
gem 'hiredis'
gem 'bootsnap'

gem 'rack-cors'
gem 'puma'
gem 'active_model_serializers'
gem 'kaminari'
gem 'attr_encrypted'
gem 'validate_url'
gem 'sidekiq'
gem 'liquid'
gem 'hashie'
gem 'mail'
gem 'activerecord-import'
gem 'http'
gem 'awesome_print'
gem 'rubyzip'
gem 'colorize'
gem 'concurrent-ruby'
gem 'groupdate'
gem 'oj'
gem 'rbnacl'

gem 'paperclip' if ENV['ENABLE_PAPERCLIP']

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  # Use bullet to optimize N+1 queries
  gem 'bullet'
  # Use rubocop for static code analysis
  gem 'rubocop'
end

group :development do
  gem 'listen', '>= 3.0.5', '< 3.3'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
