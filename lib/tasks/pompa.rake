require 'rake'

namespace :pompa do
  desc "Migrate resources from Paperclip to ActiveStorage"
  task :migrate_from_paperclip => :environment do
    Rails.eager_load!

    require 'paperclip'

    Resource.class_eval do
      has_attached_file :file
    end

    filesystem_storage = Paperclip::Attachment
      .default_options[:storage] == :filesystem

    Resource.find_each do |r|
      next if r.file.blank?

      begin
        path = filesystem_storage ? r.file.path : r.file.url

        attached = ActiveStorage::Attached::One.new("file", r,
          :dependent => :purge_later)
        attached.attach(io: open(path), filename: r.file.original_filename,
          content_type: r.file.content_type)

        r.file.clear
        r.save!
      rescue StandardError => e
        puts "Error during processing resource ##{r.id} (#{r.name}):"
        puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
      end
    end
  end

  desc "Remove Paperclip columns from models"
  task :remove_paperclip => :environment do
    Rails.eager_load!

    [:file_file_name, :file_content_type, :file_file_size,
      :file_updated_at].each do |c|
      next if !ActiveRecord::Base.connection.column_exists?(:resources, c)
      ActiveRecord::Migration.remove_column(:resources, c)
    end
  end

  desc "Clear cache"
  task :clear_cache => :environment do
    Rails.eager_load!

    Rails.cache.clear
  end 
end
