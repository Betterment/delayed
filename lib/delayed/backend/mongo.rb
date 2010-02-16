require 'mongo_mapper'

module MongoMapper
  module Document
    module ClassMethods
      def load_for_delayed_job(id)
        find!(id)
      end
    end

    module InstanceMethods
      def dump_for_delayed_job
        "#{self.class};#{id}"
      end
    end
  end
end

module Delayed
  module Backend
    module Mongo
      class Job
        include MongoMapper::Document
        include Delayed::Backend::Base
        set_collection_name 'delayed_jobs'
        
        key :priority,    Integer, :default => 0
        key :attempts,    Integer, :default => 0
        key :handler,     String
        key :run_at,      Time
        key :locked_at,   Time
        key :locked_by,   String
        key :failed_at,   Time
        key :last_error,  String
        timestamps!
        
        before_save :set_default_run_at
        
        def self.db_time_now
          MongoMapper.time_class.now.utc
        end
        
        def self.find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          where = "this.run_at <= new Date(#{db_time_now.to_f * 1000}) && (this.locked_at == null || this.locked_at < new Date(#{(db_time_now - max_run_time).to_f * 1000})) || this.locked_by == #{worker_name.to_json}"
          # all(:limit => limit, :failed_at => nil, '$where' => where)
          
          conditions = {
            '$where' => where,
            :limit => limit,
            :failed_at => nil,
            :sort => [['priority', 1], ['run_at', 1]]
          }
          
          # (conditions[:priority] ||= {})['$gte'] = Worker.min_priority if Worker.min_priority
          # (conditions[:priority] ||= {})['$lte'] = Worker.max_priority if Worker.max_priority

          all(conditions)
        end
        
        # When a worker is exiting, make sure we don't have any locked jobs.
        def self.clear_locks!(worker_name)
          collection.update({:locked_by => worker_name}, {"$set" => {:locked_at => nil, :locked_by => nil}}, :multi => true)
        end
        
        # Lock this job for this worker.
        # Returns true if we have the lock, false otherwise.
        def lock_exclusively!(max_run_time, worker = worker_name)
          now = self.class.db_time_now
          overtime = make_date(now - max_run_time.to_i)
          
          query = "this._id == #{id.to_json} && this.run_at <= #{make_date(now)} && (this.locked_at == null || this.locked_at < #{overtime} || this.locked_by == #{worker.to_json})"

          conditions = {"$where" => make_query(query)}
          collection.update(conditions, {"$set" => {:locked_at => now, :locked_by => worker}}, :multi => true)
          affected_rows = collection.find({:_id => id, :locked_by => worker}).count
          if affected_rows == 1
            self.locked_at = now
            self.locked_by = worker
            return true
          else
            return false
          end
        end
        
      private
      
        def self.make_date(date)
          "new Date(#{date.to_f * 1000})"
        end

        def make_date(date)
          self.class.make_date(date)
        end
        
        def self.make_query(string)
          "function() { return (#{string}); }"
        end

        def make_query(string)
          self.class.make_query(string)
        end
      
      
        def set_default_run_at
          self.run_at ||= self.class.db_time_now
        end
      end
    end
  end
end