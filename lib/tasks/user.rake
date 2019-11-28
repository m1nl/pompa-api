require 'rake'
require 'optparse'

namespace :user do
  desc 'Creates a user account'
  task :create => :environment do
    Rails.eager_load!
    Rails.logger = Logger.new(STDOUT)

    options = { roles: [User::Roles::AUTH] }

    parser = OptionParser.new
    parser.banner = 'Usage: rake user:create -- [options]'

    parser.on('-i', '--id CLIENT_ID', String, "User's SAML client_id (e-mail address)") do |client_id|
      options[:client_id] = client_id
    end

    parser.on('-r', '--roles [ROLES]', String, "User's roles (comma-separated), default: AUTH") do |roles|
      options[:roles] = roles.split(',')
    end

    parser.on('-h', '--help', 'Prints this help') do
      puts parser
      exit 0
    end

    if options[:client_id].blank?
      puts 'Error: CLIENT_ID not given.'
      puts parser
      exit 1
    end

    args = parser.order!(ARGV) {}
    parser.parse!(args)

    User.create!(options)

    exit 0
  end

  desc 'Deletes a user account'
  task :delete => :environment do
    Rails.eager_load!
    Rails.logger = Logger.new(STDOUT)

    options = {}

    parser = OptionParser.new
    parser.banner = 'Usage: rake user:delete -- [options]'

    parser.on('-i', '--id CLIENT_ID', String, "User's SAML client_id (e-mail address)") do |client_id|
      options[:client_id] = client_id
    end

    parser.on('-h', '--help', 'Prints this help') do
      puts parser
      exit 0
    end

    args = parser.order!(ARGV) {}
    parser.parse!(args)

    client_id = options[:client_id]

    if client_id.blank?
      puts 'Error: CLIENT_ID not given.'
      puts parser
      exit 1
    end

    user = User.where(client_id: client_id).first
    
    if user.nil?
      puts("User #{client_id} not found.")
      exit 1
    end

    user.delete

    exit 0
  end

end
