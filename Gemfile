source 'https://rubygems.org'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

if defined?(JRUBY_VERSION)
  gem 'rails', '~> 5.0.6'
  github 'jruby/activerecord-jdbc-adapter', branch: '50-stable' do
    gem 'activerecord-jdbc-adapter'
    gem 'activerecord-jdbcpostgresql-adapter'
  end
else
  gem 'rails', '~> 5.2.0'
  gem 'pg', '~> 1.0.0'
  gem 'concurrent-ruby-ext'
end

gem 'bootsnap'
gem 'rack-cors'
gem 'puma'
gem 'active_model_serializers'
gem 'kaminari'
gem 'attr_encrypted'
gem 'paperclip'
gem 'validate_url'
gem 'sidekiq'
gem 'liquid'
gem 'redis'
gem 'hiredis'
gem 'redis-rails'
gem 'hashie'
gem 'mail'
gem 'activerecord-import'
gem 'ihasa'
gem 'http'
gem 'awesome_print'
gem 'rubyzip'
gem 'colorize'
gem 'concurrent-ruby'
gem 'groupdate'

# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
# gem 'jbuilder', '~> 2.5'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 3.0'
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
# gem 'rack-cors'

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platform: :mri
end

group :development do
  gem 'listen', '~> 3.0.5'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
  # Use RSpec for specs
  gem 'rspec-rails'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
