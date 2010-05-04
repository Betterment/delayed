require 'couchrest'

class CouchRest::ExtendedDocument
  def self.load_for_delayed_job(id)
    if id
      find(id)
    else
      super
    end
  end
  
  def dump_for_delayed_job
    "#{self.class};#{id}"
  end
end

module Delayed
  module Backend
    module CouchRest
    
      @@server = nil
      @@db = nil
    
      class Job < ::CouchRest::ExtendedDocument
        include Delayed::Backend::Base
        use_database ::CouchRest.db
        
        property :priority
        property :attempts
        property :handler
        property :run_at
        property :locked_at
        property :locked_by
        property :failed_at
        property :last_error
        timestamps!
        
        view_by :locked_by
        view_by(:locked_at, :run_at,
          :map => "function(doc){" +
          " if(doc['couchrest-type'] == 'Job' && doc.run_at) {" +
          " var locked_at = doc.locked_at || '';" +
          " emit([locked_at, doc.run_at], null);}" +
          " }")
        
        set_callback :save, :before, :set_default_run_at

        def self.after_fork
          ::CouchRest.server = CouchRest.new('http://localhost:5984')
          ::CouchRest.db = SERVER.database!('delayed_job')
        end
        
        def self.db_time_now
          Time.now.utc
        end
        
        def self.find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          by_locked_at_and_run_at :start_key => [''], :end_key => ['', db_time_now], :limit => limit
        end
        
        # When a worker is exiting, make sure we don't have any locked jobs.
        def self.clear_locks!(worker_name)
          docs = by_locked_by :startkey => [worker_name], :endkey => [worker_name, {}]
          docs.each { |doc| doc.locked_by, doc.locked_at = nil, nil; }
          database.bulk_save docs
        end
        
        # Lock this job for this worker.
        # Returns true if we have the lock, false otherwise.
        def lock_exclusively!(max_run_time, worker = worker_name)
          locked_at, locked_by = self.class.db_time_now, worker
          save
        end
        
        def self.delete_all
          Delayed::Job.auto_migrate!
        end
        
        def self.find id
          get id
        end
        
        def update_attributes(attributes)
          attributes.each do |k,v|
            self[k] = v
          end
          self.save
        end
      end
    end
  end
end
