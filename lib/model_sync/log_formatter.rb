# frozen_string_literal: true

module ModelSync
  class LogFormatter
    def call(severity, time, program_name, message)
      "#{time.utc.iso8601(3)} pid=#{ModelSync.pid} " +
        "tid=#{ModelSync.tid} name=#{ModelSync.current_name} " +
        "#{severity}: #{message}\n"
    end
  end
end
