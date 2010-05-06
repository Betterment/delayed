require 'couchrest'

#extent couchrest to handle delayed_job serialization.
class CouchRest::ExtendedDocument
  def reload; end
  def self.find(id)
    get id
  end  
  def dump_for_delayed_job
    "#{self.class};#{id}"
  end
  def self.load_for_delayed_job(id)
    (id)? get(id) : super 
  end  
  def ==(other)
    if other.is_a? ::CouchRest::ExtendedDocument
      self['_id'] == other['_id']
    else
      super
    end
  end  
end

#couchrest adapter
module Delayed
  module Backend
    module CouchRest
      class Job < ::CouchRest::ExtendedDocument
        include Delayed::Backend::Base
        use_database ::CouchRest::Server.new.database('delayed_job')

        property :handler
        property :last_error                
        property :priority, :default => 0
        property :attempts, :default => 0
        property :locked_by, :default => ''
        property :run_at, :cast_as => 'Time'
        property :locked_at, :cast_as => 'Time', :default => ''
        property :failed_at, :cast_as => 'Time', :default => ''
        timestamps!

        set_callback :save, :before, :set_default_run_at

        view_by(:failed_at, :locked_by, :run_at,
                :map => "function(doc){" +
                "          if(doc['couchrest-type'] == 'Delayed::Backend::CouchRest::Job') {" +
                "            emit([doc.failed_at, doc.locked_by, doc.run_at], null);}" +
                "        }")
        view_by(:failed_at, :locked_at, :run_at,
                :map => "function(doc){" +
                "          if(doc['couchrest-type'] == 'Delayed::Backend::CouchRest::Job') {" +
                "            emit([doc.failed_at, doc.locked_at, doc.run_at], null);}" +
                "        }")        

        def self.db_time_now; Time.now; end    
        def self.find_available(worker_name, limit = 5, max_run_time = ::Delayed::Worker.max_run_time)
          ready = ready_jobs
          mine = my_jobs worker_name
          expire = expired_jobs max_run_time
          jobs = (ready + mine + expire)[0..limit-1].sort_by { |j| j.priority }
          jobs = jobs.find_all { |j| j.priority >= Worker.min_priority } if Worker.min_priority
          jobs = jobs.find_all { |j| j.priority <= Worker.max_priority } if Worker.max_priority
          jobs
        end
        def self.clear_locks!(worker_name)
          jobs = my_jobs worker_name
          jobs.each { |j| j.locked_by, j.locked_at = '', ''; }
          database.bulk_save jobs
        end
        def self.delete_all
          database.bulk_save all.each { |doc| doc['_deleted'] = true }
        end
        
        def lock_exclusively!(max_run_time, worker = worker_name)
          return false if locked_by_other?(worker) and not expired?(max_run_time)
          case
          when locked_by_me?(worker)
            self.locked_at = self.class.db_time_now
          when (unlocked? or (locked_by_other?(worker) and expired?(max_run_time)))
            self.locked_at, self.locked_by = self.class.db_time_now, worker
          end
          save
        rescue RestClient::Conflict
          false
        end
        
        private
        def self.ready_jobs
          options = {:startkey => ['', ''], :endkey => ['', '', db_time_now]}
          by_failed_at_and_locked_by_and_run_at options
        end
        def self.my_jobs(worker_name)
          options = {:startkey => ['', worker_name], :endkey => ['', worker_name, {}]}
          by_failed_at_and_locked_by_and_run_at options
        end
        def self.expired_jobs(max_run_time)
          options = {:startkey => ['','0'], :endkey => ['', db_time_now - max_run_time, db_time_now]}
          by_failed_at_and_locked_at_and_run_at options
        end
        def unlocked?; locked_by == ''; end
        def expired?(time); locked_at < self.class.db_time_now - time; end
        def locked_by_me?(worker); locked_by != '' and locked_by == worker; end        
        def locked_by_other?(worker); locked_by != '' and locked_by != worker; end
      end
    end
  end
end
