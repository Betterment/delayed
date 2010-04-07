shared_examples_for 'a backend' do
  def create_job(opts = {})
    @backend.create(opts.merge(:payload_object => SimpleJob.new))
  end

  before do
    Delayed::Worker.max_priority = nil
    Delayed::Worker.min_priority = nil
    SimpleJob.runs = 0
  end
  
  it "should set run_at automatically if not set" do
    @backend.create(:payload_object => ErrorJob.new ).run_at.should_not be_nil
  end

  it "should not set run_at automatically if already set" do
    later = @backend.db_time_now + 5.minutes
    @backend.create(:payload_object => ErrorJob.new, :run_at => later).run_at.should be_close(later, 1)
  end

  it "should raise ArgumentError when handler doesn't respond_to :perform" do
    lambda { @backend.enqueue(Object.new) }.should raise_error(ArgumentError)
  end

  it "should increase count after enqueuing items" do
    @backend.enqueue SimpleJob.new
    @backend.count.should == 1
  end
  
  it "should be able to set priority when enqueuing items" do
    @job = @backend.enqueue SimpleJob.new, 5
    @job.priority.should == 5
  end

  it "should be able to set run_at when enqueuing items" do
    later = @backend.db_time_now + 5.minutes
    @job = @backend.enqueue SimpleJob.new, 5, later
    @job.run_at.should be_close(later, 1)
  end

  it "should work with jobs in modules" do
    M::ModuleJob.runs = 0
    job = @backend.enqueue M::ModuleJob.new
    lambda { job.invoke_job }.should change { M::ModuleJob.runs }.from(0).to(1)
  end
                   
  it "should raise an DeserializationError when the job class is totally unknown" do
    job = @backend.new :handler => "--- !ruby/object:JobThatDoesNotExist {}"
    lambda { job.payload_object.perform }.should raise_error(Delayed::Backend::DeserializationError)
  end

  it "should try to load the class when it is unknown at the time of the deserialization" do
    job = @backend.new :handler => "--- !ruby/object:JobThatDoesNotExist {}"
    job.should_receive(:attempt_to_load).with('JobThatDoesNotExist').and_return(true)
    lambda { job.payload_object.perform }.should raise_error(Delayed::Backend::DeserializationError)
  end

  it "should try include the namespace when loading unknown objects" do
    job = @backend.new :handler => "--- !ruby/object:Delayed::JobThatDoesNotExist {}"
    job.should_receive(:attempt_to_load).with('Delayed::JobThatDoesNotExist').and_return(true)
    lambda { job.payload_object.perform }.should raise_error(Delayed::Backend::DeserializationError)
  end

  it "should also try to load structs when they are unknown (raises TypeError)" do
    job = @backend.new :handler => "--- !ruby/struct:JobThatDoesNotExist {}"
    job.should_receive(:attempt_to_load).with('JobThatDoesNotExist').and_return(true)
    lambda { job.payload_object.perform }.should raise_error(Delayed::Backend::DeserializationError)
  end

  it "should try include the namespace when loading unknown structs" do
    job = @backend.new :handler => "--- !ruby/struct:Delayed::JobThatDoesNotExist {}"
    job.should_receive(:attempt_to_load).with('Delayed::JobThatDoesNotExist').and_return(true)
    lambda { job.payload_object.perform }.should raise_error(Delayed::Backend::DeserializationError)
  end
  
  describe "find_available" do
    it "should not find failed jobs" do
      @job = create_job :attempts => 50, :failed_at => @backend.db_time_now
      @backend.find_available('worker', 5, 1.second).should_not include(@job)
    end
    
    it "should not find jobs scheduled for the future" do
      @job = create_job :run_at => (@backend.db_time_now + 1.minute)
      @backend.find_available('worker', 5, 4.hours).should_not include(@job)
    end
    
    it "should not find jobs locked by another worker" do
      @job = create_job(:locked_by => 'other_worker', :locked_at => @backend.db_time_now - 1.minute)
      @backend.find_available('worker', 5, 4.hours).should_not include(@job)
    end
    
    it "should find open jobs" do
      @job = create_job
      @backend.find_available('worker', 5, 4.hours).should include(@job)
    end
    
    it "should find expired jobs" do
      @job = create_job(:locked_by => 'worker', :locked_at => @backend.db_time_now - 2.minutes)
      @backend.find_available('worker', 5, 1.minute).should include(@job)
    end
    
    it "should find own jobs" do
      @job = create_job(:locked_by => 'worker', :locked_at => (@backend.db_time_now - 1.minutes))
      @backend.find_available('worker', 5, 4.hours).should include(@job)
    end

    it "should find only the right amount of jobs" do
      10.times { create_job }
      @backend.find_available('worker', 7, 4.hours).should have(7).jobs
    end
  end
  
  context "when another worker is already performing an task, it" do

    before :each do
      @job = @backend.create :payload_object => SimpleJob.new, :locked_by => 'worker1', :locked_at => @backend.db_time_now - 5.minutes
    end

    it "should not allow a second worker to get exclusive access" do
      @job.lock_exclusively!(4.hours, 'worker2').should == false
    end

    it "should allow a second worker to get exclusive access if the timeout has passed" do
      @job.lock_exclusively!(1.minute, 'worker2').should == true
    end      
    
    it "should be able to get access to the task if it was started more then max_age ago" do
      @job.locked_at = 5.hours.ago
      @job.save

      @job.lock_exclusively! 4.hours, 'worker2'
      @job.reload
      @job.locked_by.should == 'worker2'
      @job.locked_at.should > 1.minute.ago
    end

    it "should not be found by another worker" do
      @backend.find_available('worker2', 1, 6.minutes).length.should == 0
    end

    it "should be found by another worker if the time has expired" do
      @backend.find_available('worker2', 1, 4.minutes).length.should == 1
    end

    it "should be able to get exclusive access again when the worker name is the same" do
      @job.lock_exclusively!(5.minutes, 'worker1').should be_true
      @job.lock_exclusively!(5.minutes, 'worker1').should be_true
      @job.lock_exclusively!(5.minutes, 'worker1').should be_true
    end                                        
  end
  
  context "when another worker has worked on a task since the job was found to be available, it" do

    before :each do
      @job = @backend.create :payload_object => SimpleJob.new
      @job_copy_for_worker_2 = @backend.find(@job.id)
    end

    it "should not allow a second worker to get exclusive access if already successfully processed by worker1" do
      @job.destroy
      @job_copy_for_worker_2.lock_exclusively!(4.hours, 'worker2').should == false
    end

    it "should not allow a second worker to get exclusive access if failed to be processed by worker1 and run_at time is now in future (due to backing off behaviour)" do
      @job.update_attributes(:attempts => 1, :run_at => 1.day.from_now)
      @job_copy_for_worker_2.lock_exclusively!(4.hours, 'worker2').should == false
    end
  end

  context "#name" do
    it "should be the class name of the job that was enqueued" do
      @backend.create(:payload_object => ErrorJob.new ).name.should == 'ErrorJob'
    end

    it "should be the method that will be called if its a performable method object" do
      @job = Story.send_later(:create)
      @job.name.should == "Story.create"
    end

    it "should be the instance method that will be called if its a performable method object" do
      @job = Story.create(:text => "...").send_later(:save)
      @job.name.should == 'Story#save'
    end
  end
  
  context "worker prioritization" do
    before(:each) do
      Delayed::Worker.max_priority = nil
      Delayed::Worker.min_priority = nil
    end

    it "should fetch jobs ordered by priority" do
      10.times { @backend.enqueue SimpleJob.new, rand(10) }
      jobs = @backend.find_available('worker', 10)
      jobs.size.should == 10
      jobs.each_cons(2) do |a, b| 
        a.priority.should <= b.priority
      end
    end

    it "should only find jobs greater than or equal to min priority" do
      min = 5
      Delayed::Worker.min_priority = min
      10.times {|i| @backend.enqueue SimpleJob.new, i }
      jobs = @backend.find_available('worker', 10)
      jobs.each {|job| job.priority.should >= min}
    end

    it "should only find jobs less than or equal to max priority" do
      max = 5
      Delayed::Worker.max_priority = max
      10.times {|i| @backend.enqueue SimpleJob.new, i }
      jobs = @backend.find_available('worker', 10)
      jobs.each {|job| job.priority.should <= max}
    end
  end
  
  context "clear_locks!" do
    before do
      @job = create_job(:locked_by => 'worker', :locked_at => @backend.db_time_now)
    end
    
    it "should clear locks for the given worker" do
      @backend.clear_locks!('worker')
      @backend.find_available('worker2', 5, 1.minute).should include(@job)
    end
    
    it "should not clear locks for other workers" do
      @backend.clear_locks!('worker1')
      @backend.find_available('worker1', 5, 1.minute).should_not include(@job)
    end
  end
  
  context "unlock" do
    before do
      @job = create_job(:locked_by => 'worker', :locked_at => @backend.db_time_now)
    end

    it "should clear locks" do
      @job.unlock
      @job.locked_by.should be_nil
      @job.locked_at.should be_nil
    end
  end
  
  context "large handler" do
    @@text = %{Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus eu vehicula augue. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Quisque odio lectus, volutpat sed dictum rutrum, interdum aliquam neque. Vivamus quis velit nisi, quis dictum purus. Duis magna nisi, faucibus nec molestie vitae, dictum eget odio. Nunc nulla mauris, vestibulum at dapibus nec, dapibus et lectus. Nullam sapien lacus, consectetur eget mattis in, rhoncus sed ipsum. Nullam nec nibh nisl. Integer ut erat in arcu feugiat semper. Nulla gravida sapien quam. Vestibulum pharetra elementum posuere. Fusce mattis justo auctor nibh facilisis vitae consectetur nibh vehicula.

    Ut at pharetra justo. Donec dictum ornare tortor in feugiat. Sed ac purus sem. Aenean dignissim, erat vel bibendum mollis, elit neque mollis mauris, vitae pretium diam enim non leo. Aliquam aliquet, odio id iaculis varius, metus nibh fermentum sapien, a euismod turpis lectus sit amet turpis. Morbi sapien est, scelerisque in placerat in, varius nec mauris. Aliquam erat volutpat. Quisque suscipit tincidunt libero, sed tincidunt libero iaculis et. Vivamus sed faucibus elit. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vivamus dignissim sem sed tortor semper et lacinia leo viverra. Nulla nec quam at arcu ullamcorper imperdiet vitae in ligula. Quisque placerat vulputate orci sit amet tempor. Duis sed quam nulla. Cras quis mi nibh, at euismod velit. Etiam nec nunc libero, sed condimentum diam.

    Duis nec mauris in est suscipit viverra a in nibh. Suspendisse nec nulla tortor. Etiam et nulla tellus. Nam feugiat adipiscing commodo. Curabitur scelerisque varius lacus non hendrerit. Vivamus nec enim non turpis auctor tempus sit amet in nisi. Sed ligula nulla, condimentum sed tempor vel, imperdiet id mauris. Quisque mollis ante eu magna tempus porttitor. Integer est libero, consectetur sed tristique a, scelerisque id risus. Donec lacinia justo eget diam fringilla vitae egestas dolor feugiat. Vivamus massa ante, mattis et hendrerit nec, dictum vitae nulla. Pellentesque at nisl et odio suscipit ullamcorper cursus quis enim. Ut nec tellus molestie erat dignissim mollis. Curabitur quis ipsum sapien, sed tincidunt massa. Vestibulum volutpat pretium fringilla.

    Integer at lorem sit amet nibh suscipit euismod et ut ante. Maecenas feugiat hendrerit dolor, eget egestas velit consequat eget. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Suspendisse ut nunc odio. Vivamus semper, sem vitae sollicitudin auctor, leo mi vulputate augue, eget venenatis libero nunc ut dolor. Phasellus vulputate, metus et dapibus tempus, tellus arcu ullamcorper leo, porttitor dictum lectus turpis blandit sapien. Pellentesque et accumsan justo. Maecenas elit nisi, tincidunt eget consequat a, laoreet et magna. Pellentesque venenatis felis ut massa ultrices bibendum. Duis vulputate tempor leo at bibendum. Curabitur aliquet, turpis sit amet porta porttitor, nibh mi vehicula dolor, suscipit aliquet mi augue quis magna. Praesent tellus turpis, malesuada at ultricies id, feugiat a urna. Curabitur sed mi magna.

    Quisque adipiscing dignissim mollis. Aenean blandit, diam porttitor bibendum bibendum, leo neque tempus risus, in rutrum dolor elit a lorem. Aenean sollicitudin scelerisque ullamcorper. Nunc tristique ultricies nunc et imperdiet. Duis vitae egestas mauris. Suspendisse odio nisi, accumsan vel volutpat nec, aliquam vitae odio. Praesent elementum fermentum suscipit. Quisque quis tellus eu tellus bibendum luctus a quis nunc. Praesent dictum velit sed lacus dapibus ut ultricies mauris facilisis. Vivamus bibendum, ipsum sit amet facilisis consequat, leo lectus aliquam augue, eu consectetur magna nunc gravida sapien. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis tempor nisl ac odio molestie ut tincidunt purus varius. Nunc quis lorem nibh, vestibulum cursus lorem. Nunc sit amet est ut magna suscipit tempor vitae a augue.}

    before do
      @job = @backend.enqueue Delayed::PerformableMethod.new(@@text, :length, {})
    end
    
    it "should have an id" do
      @job.id.should_not be_nil
    end
  end
end
