source 'https://rubygems.org'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?('/')
  "https://github.com/#{repo_name}.git"
end

gem 'rails', '~> 5.2.0'

if defined?(JRUBY_VERSION)
  github 'jruby/activerecord-jdbc-adapter', branch: '52-stable' do
    gem 'activerecord-jdbcpostgresql-adapter', :platform => :jruby
  end
else
  gem 'pg', '~> 1.0.0'
  gem 'redis', '~> 4.0'

  gem 'concurrent-ruby-ext'
  gem 'hiredis'
  gem 'bootsnap'
end

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

gem 'paperclip' if ENV['ENABLE_PAPERCLIP']

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
