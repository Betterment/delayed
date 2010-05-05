require 'couchrest'

#make sure database exists. If not create it.
CouchRest::Server.new.database!('delayed_job')

#extent couchrest to handle delayed_job serialization.
class CouchRest::ExtendedDocument
  def self.load_for_delayed_job(id)
    (id)? get(id) : super 
  end
  
  def dump_for_delayed_job
    "#{self.class};#{id}"
  end
end

#couchrest adapter
module Delayed
  module Backend
    module CouchRest
      class Job < ::CouchRest::ExtendedDocument
        include Delayed::Backend::Base
        use_database ::CouchRest::Server.new.database('delayed_job')
        
        property :priority
        property :attempts
        property :handler
        property :run_at
        property :locked_at
        property :locked_by
        property :failed_at
        property :last_error
        timestamps!

        view_by(:locked_by, :run_at,
                :map => "function(doc){" +
                "          if(doc['couchrest-type'] == 'Delayed::Backend::CouchRest::Job' && doc.run_at) {" +
                "            var locked_by = doc.locked_by || '';" +
                "            emit([locked_by, doc.run_at], null);}" +
                "        }")

        set_callback :save, :before, :set_default_run_at
        set_callback :save, :before, :set_default_attempts
        set_callback :save, :before, :set_default_priority  

        def self.db_time_now; Time.now; end    
        def self.find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          by_locked_by_and_run_at :start_key => [''], :end_key => ['', db_time_now], :limit => limit
        end
        def self.clear_locks!(worker_name)
          docs = by_locked_by_and_run_at :startkey => [worker_name], :endkey => [worker_name, {}]
          docs.each { |doc| doc.locked_by, doc.locked_at = nil, nil; }
          database.bulk_save docs
        end
        def self.delete_all
          database.bulk_save all.each { |doc| doc['_deleted'] = true }
        end
        
        def lock_exclusively!(max_run_time, worker = worker_name)
          self.locked_at, self.locked_by = self.class.db_time_now, worker    
          save
        end
        def set_default_priority
          self.priority = 0 if priority.nil?
        end
        def set_default_attempts
          self.attempts = 0 if attempts.nil?
        end
      end
    end
  end
end
