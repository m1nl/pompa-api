class WorkerJob < ApplicationJob
  include Pompa::Worker

  SUFFIX = 'WorkerJob'.freeze

  class << self
    def model_class_name
      self.name.split(SUFFIX).first
    end

    def model_class
      model_class_name.constantize
    end
  end

  protected
    def claim
      model_class.claim_jid(@instance_id, job_id) ||
        (raise Pompa::Worker::InvalidStateException.new(
           'unable to claim jid for model instance'))
    end

    def release
      model_class.release_jid(@instance_id, job_id) ||
        (raise Pompa::Worker::InvalidStateException.new(
           'unable to release jid for model instance'))
    end

    def resync
      job_id = self.job_id
      ActiveRecord::Base.connection.clear_query_cache

      @model = model_class.find_by_id(@instance_id) ||
        (raise Pompa::Worker::InvalidInstanceException.new(
           'instance not found'))
      model.claim_jid(job_id) ||
        (raise Pompa::Worker::InvalidStateException.new(
           'unable to claim jid for model instance'))
      model.tap do |m|
        m.trigger_resync = false
        m.define_singleton_method(:reload) do |opts = {}|
          begin
            super(opts)
          rescue ActiveRecord::RecordNotFound
            raise Pompa::Worker::InvalidInstanceException.new(
              'instance not found')
          end

          claim_jid(job_id) ||
            (raise Pompa::Worker::InvalidStateException.new(
               'unable to claim jid for model instance'))
        end
      end
    end

    def model
      @model
    end

    [:model_class_name, :model_class].each { |m| define_method m do
      self.class.public_send(m)
    end }
end
