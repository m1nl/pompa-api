class WorkerResponseSerializer < ApplicationSerializer
  attributes :id, :status, :value, :broadcast, :result, :worker_id
  belongs_to :worker, class_name: 'Worker'

  def links
    links = super
    links.merge!({ :worker => Rails.application.routes
      .url_helpers.url_for(:controller => :workers, :action => :show,
        :only_path => true, :id => object.worker_id) }) if object.worker_id
  end
end
