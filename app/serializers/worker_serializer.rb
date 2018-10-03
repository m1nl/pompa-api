class WorkerSerializer < ApplicationSerializer
  attributes :id, :instance_id, :worker_class_name, :message_queue, :started_at, :last_active, :worker_state
end
