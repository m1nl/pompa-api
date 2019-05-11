class ApplicationJob < ActiveJob::Base
  around_perform do |_job, block|
    Bullet.profile do
      block.call
    end
  end if defined?(Bullet)
end
