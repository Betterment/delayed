Mongoid::Document.class_eval do
  yaml_as "tag:ruby.yaml.org,2002:Mongoid"
  
  def self.yaml_new(klass, tag, val)
    begin
      klass.find(val['attributes']['_id'])
    rescue Mongoid::Errors::DocumentNotFound
      nil
    end
  end
  
  def to_yaml_properties
    ['@attributes']
  end
end

module Delayed
  module Backend
    module Mongoid
      class Job
        include ::Mongoid::Document
        include ::Mongoid::Timestamps
        include Delayed::Backend::Base
        field :priority,    :type=> Integer, :default => 0
        field :attempts,    :type=> Integer, :default => 0
        field :handler,     :type=> String
        field :run_at,      :type=> Time
        field :locked_at,   :type=> Time
        field :locked_by,   :type=> String, :index => true
        field :failed_at,   :type=> Time
        field :last_error,  :type=> String
      
      
        before_save :set_default_run_at
        
        def self.before_fork
          ::Mongoid.master.connection.close
        end

        def self.after_fork
          ::Mongoid.master.connection.connect_to_master
        end
        
        def self.db_time_now
          Time.now.utc
        end
        
        def self.find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          right_now = db_time_now

          conditions = {:run_at  => {"$lte" => right_now}, :failed_at => nil}
          (conditions[:priority] ||= {})['$gte'] = Worker.min_priority.to_i if Worker.min_priority
          (conditions[:priority] ||= {})['$lte'] = Worker.max_priority.to_i if Worker.max_priority
         
          
          where = "this.locked_at == null || this.locked_at < #{make_date(right_now - max_run_time)}"
          results = self.where(conditions.merge(:locked_by => worker_name)).limit(-limit).order_by([['priority', 1], ['run_at', 1]]).to_a
          results += self.where(conditions.merge('$where' => where)).limit(-limit+results.size).order_by([['priority', 1], ['run_at', 1]]).to_a if results.size < limit
          results
        end
        # When a worker is exiting, make sure we don't have any locked jobs.
        def self.clear_locks!(worker_name)
          self.collection.update({:locked_by => worker_name}, {"$set" => {:locked_at => nil, :locked_by => nil}}, :multi => true)
        end
        
        # Lock this job for this worker.
        # Returns true if we have the lock, false otherwise.
        def lock_exclusively!(max_run_time, worker = worker_name)
          right_now = self.class.db_time_now
          overtime = right_now - max_run_time.to_i
          
          query = "this.locked_at == null || this.locked_at < #{make_date(overtime)} || this.locked_by == #{worker.to_json}"
          conditions = {:_id => id, :run_at => {"$lte" => right_now}, "$where" => query}
          
          self.collection.update(conditions, {"$set" => {:locked_at => right_now, :locked_by => worker}})
          affected_rows = self.collection.find({:_id => id, :locked_by => worker}).count
          if affected_rows == 1
            self.locked_at = right_now
            self.locked_by = worker
            return true
          else
            return false
          end
        end
        
        private

        def self.make_date(date_or_seconds)
        "new Date(#{date_or_seconds.to_f * 1000})"
        end

        def make_date(date)
          self.class.make_date(date)
        end
      end
    end
  end
end