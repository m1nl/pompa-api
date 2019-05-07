module Pompa
  class LogFormatter
   def call(severity, time, progname, msg = '')
     return '' if msg.blank?
  
     if progname.present?
       return "timestamp='#{time}' level=#{severity} progname='#{progname}' #{processed_message(msg)}\n"
     end
  
     "timestamp='#{time}' level=#{severity} #{processed_message(msg)}\n"
   end
  
   private
   
   def processed_message(msg)
    return msg.map { |k, v| "#{k}='#{v.strip}'" }.join(' ') if msg.is_a?(Hash)
  
    "message='#{msg.strip}'"
   end
  end
end
