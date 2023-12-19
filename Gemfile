source 'https://rubygems.org'
git_source(:github) { |repo| 'https://github.com/#{repo}.git' }

gem 'rails', '~> 7.0.3'
gem 'bootsnap', require: false
gem 'rake'

gem 'pg'

gem 'redis'
gem 'hiredis-client'

gem 'concurrent-ruby-ext'
gem 'rack-cors'

gem 'puma'
gem 'active_model_serializers'
gem 'kaminari'
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
gem 'thread_safe'

gem 'jwt'
gem 'pundit'
gem 'ruby-saml'

gem 'aws-sdk-s3'
gem 'azure-storage-blob'

gem 'paperclip' if ENV['ENABLE_PAPERCLIP']

group :development, :test do
  gem 'listen'
  # Use rubocop for static code analysis
  gem 'rubocop'
  # Use bullet to optimize N+1 queries
  #gem 'bullet'
end

group :development do
  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  #gem 'spring'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[ mingw mswin x64_mingw jruby ]
