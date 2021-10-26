Delayed
=======
[![Gem Version](https://badge.fury.io/rb/delayed.svg)](https://rubygems.org/gems/delayed)
![CI](https://github.com/Betterment/delayed/workflows/CI/badge.svg)

**`Delayed` is a multi-threaded, SQL-driven ActiveJob backend used at
[Betterment](https://betterment.com) to process millions of background jobs per day.**

It supports **postgres**, **mysql**, and **sqlite**, and is designed to be:

- **Reliable**, with co-transactional job enqueues and guaranteed, at-least-once execution
- **Scalable**, with an optimized pickup query and concurrent job execution
- **Resilient**, with built-in retry mechanisms, exponential back-off, and failed job preservation
- **Maintainable**, with robust instrumentation, continuous monitoring, and priority-based alerting

For an overview of how Betterment uses `delayed` to build resilience into distributed systems, read
the
[announcement blog post](https://www.betterment.com/resources/delayed-resilient-background-jobs-on-rails/),
and/or check out the talk ✨[Can I break this?](https://www.youtube.com/watch?v=TuhS13rBoVY)✨
given at RailsConf 2021!


### Why `Delayed`?

The `delayed` gem is a targeted fork of both `delayed_job` and `delayed_job_active_record`,
combining them into a single library. It is designed for applications with the kinds of operational
needs seen at Betterment, and includes numerous features extracted from Betterment's codebases, such
as:

- Multithreaded job execution via
  [`concurrent-ruby`](https://github.com/ruby-concurrency/concurrent-ruby)
- A highly optimized, `SKIP LOCKED`-based pickup query (on postgres)
- Built-in instrumentation and continuous monitoring via a new `monitor` process
- Named priority ranges, defaulting to `:interactive`, `:user_visible`, `:eventual`, and `:reporting`
- Priority-based alerting threshholds for job age, run time, and attempts
- An experimental autoscaling metric, for use by a horizontal autoscaler (we use Kubernetes)
- A custom adapter that extends `ActiveJob` with `Delayed`-specific behaviors

This gem benefits immensely from the **many years** of development, maintenance, and community
support that have gone into `delayed_job`, and many of the core DJ APIs (like `.delay`) are still
available in `delayed` as undocumented features. Over time, these APIs may be removed as this gem
focuses itself around `ActiveJob`-based usage, but the aim will be to provide bidirectional
migration paths where possible.

## Table of Contents

* [Getting Started](#getting-started)
* [Basic Usage](#basic-usage)
  * [Running a worker process](#running-a-worker-process)
  * [Enqueuing Jobs](#enqueuing-jobs)
* [Operational Considerations](#operational-considerations)
* [Monitoring Jobs & Workers](#monitoring-jobs--workers)
  * [Lifecycle Hooks](#lifecycle-hooks)
  * [Priority-based Alerting Threshholds](#priority-based-alerting-threshholds)
  * [Continuous Monitoring](#continuous-monitoring)
* [Configuration](#configuration)
* [Migrating from other ActiveJob backends](#migrating-from-other-activejob-backends)
  * [Migrating from DelayedJob](#migrating-from-delayedjob)
* [How to Contribute](#how-to-contribute)

## Getting Started

This gem is designed to work with Rails 5.2+ and Ruby 2.6+ on postgres 9.5+ or mysql 5.6+

### Installation

Add the following to your Gemfile:

```
gem 'delayed'
```

Then run `bundle install`.

Before you can enqueue and run jobs, you will need a jobs table. You can create this table by
running the following command:

```bash
rails generate delayed:migration
rails db:migrate
```

Then, to use this background job processor with ActiveJob, add the following to your application config:

```ruby
config.active_job.queue_adapter = :delayed
```

See the [Rails guide](http://guides.rubyonrails.org/active_job_basics.html#setting-the-backend) for
more details.

## Basic Usage

### Running a worker process

In order for any jobs to execute, you must first start a worker process, which will work off jobs:

```
rake delayed:work
```

By default, a worker process will pick up 2 jobs at a time (ordered by priority) and run each in a
separate thread. To change the number of jobs picked up (and, in turn, increase the size of the
thread pool), use the `MAX_CLAIMS` environment variable:

```bash
MAX_CLAIMS=5 rake delayed:work
```

Work off specific queues by setting the `QUEUE` or `QUEUES` environment variable:

```bash
QUEUE=tracking rake delayed:work
QUEUES=mailers,tasks rake delayed:work
```

You can stop the worker with `CTRL-C` or by sending a `SIGTERM` signal to the process. The worker
will attempt to complete outstanding jobs and gracefully shutdown. Some platforms (like Heroku) will
send a `SIGKILL` after a designated timeout, which will immediately terminate the process and may
result in long-running jobs remaining locked until `Delayed::Worker.max_run_time` has elapsed. (By
default this is 20 minutes.)

### Enqueuing Jobs

The recommended usage of this gem is via `ActiveJob`. You can define a job like so:

```ruby
def MyJob < ApplicationJob
  def perform(any: 'arguments')
    # do something here
  end
end
```

Then, enqueue the job with `perform_later`:

```ruby
MyJob.perform_later(arguments: 'go here')
```

Jobs will be enqueued to the `delayed_jobs` table, which can be accessed via
the `Delayed::Job` ActiveRecord model using standard ActiveRecord query methods
(`.find`, `.where`, etc).

To override specific columns or parameters of the job, use `set`:

```ruby
MyJob.set(priority: 11).perform_later(some_more: 'arguments')
MyJob.set(queue: 'video_encoding').perform_later(video)
MyJob.set(wait: 3.hours).perform_later
MyJob.set(wait_until: 1.day.from_now).perform_later
```

Priority ranges are mapped to configurable shorthand names:

```ruby
MyJob.set(priority: :interactive).perform_later
MyJob.set(priority: :user_visible).perform_later
MyJob.set(priority: :eventual).perform_later
MyJob.set(priority: :reporting).perform_later

Delayed::Job.last.priority.user_visible? # => false
Delayed::Priority.new(99).reporting? # => true
Delayed::Priority.new(11).to_i # => 11
Delayed::Priority.new(3).to_s # => 'interactive'
```

**To change the default priority names, or to adjust other aspects of job
execution, see the [Configuration](#configuration) section below.**

#### Other ActiveJob Features

All other ActiveJob features should work out of the box, such as the `queue_as`
and `queue_with_priority` class-level directives:

```ruby
class MyJob < ApplicationJob
  queue_as 'some_other_queue'
  queue_with_priority 42

  # ...
end
```

ActiveJob also supports the following lifecycle hooks:

- [before_enqueue](https://edgeapi.rubyonrails.org/classes/ActiveJob/Callbacks/ClassMethods.html#method-i-before_enqueue)
- [around_enqueue](https://edgeapi.rubyonrails.org/classes/ActiveJob/Callbacks/ClassMethods.html#method-i-around_enqueue)
- [after_enqueue](https://edgeapi.rubyonrails.org/classes/ActiveJob/Callbacks/ClassMethods.html#method-i-after_enqueue)
- [before_perform](https://edgeapi.rubyonrails.org/classes/ActiveJob/Callbacks/ClassMethods.html#method-i-before_perform)
- [around_perform](https://edgeapi.rubyonrails.org/classes/ActiveJob/Callbacks/ClassMethods.html#method-i-around_perform)
- [after_perform](https://edgeapi.rubyonrails.org/classes/ActiveJob/Callbacks/ClassMethods.html#method-i-after_perform)

**Read more about ActiveJob usage on the [Active Job
Basics](https://guides.rubyonrails.org/active_job_basics.html) documentation page.**


## Operational Considerations

`Delayed` has been shaped around Betterment's day-to-day operational needs. In order to benefit from
these design decisions, there are a few things you'll want to keep in mind.

#### Co-transactionality

The `:delayed` job backend is designed for **co-transactional** job enqueues.  This means that you
can safely enqueue jobs inside of [ACID](https://en.wikipedia.org/wiki/ACID)-compliant business
operations, like so:

```ruby
def save
  ActiveRecord::Base.transaction do
    user.lock!

    if user.update(email: new_email)
      EmailChangeJob.perform_later(user, new_email, old_email)

      true
    else
      false
    end
  end
end
```

If the transaction rolls back, the enqueued job will _also_ roll back, ensuring that the entire
operation is all-or-nothing.  A job will never become visible to a worker until the transaction
commits.

Important: the above assumes that the connection used by the transaction is the one provided by
`ActiveRecord::Base`.  (Support for enqueuing jobs via other database connections is possible, but
is not yet exposed as a configuration.)

#### At-Least-Once Delivery

Each job is guaranteed to run _at least once_, but under certain conditions may run more than once.
As such, you'll want to ensure that your jobs are
[idempotent](https://en.wikipedia.org/wiki/Idempotence), meaning they can be safely repeated,
regardless of the outcome of any prior attempts.

#### When Jobs Fail

Unlike other job queue backends, `delayed` will **not** delete failing jobs by default. These are
jobs that have reached their `max_attempts` (25 by default), and they will remain in the queue until
you manually intervene.

The general idea is that you should treat these as operational issues (like an error on your
bugtracker), and you should aim to resolve the issue by making the job succeed. This might involve
shipping a bugfix, making a data change, or updating the job's implementation to handle certain
corner cases more gracefully (perhaps by no-opping). When you're ready to re-run, you may clear the
`failed_at` column and reset `attempts` to 0:

```ruby
Delayed::Job.find(failing_job_id).update!(failed_at: nil, attempts: 0, run_at: Time.zone.now)
```

## Monitoring Jobs & Workers

`Delayed` will emit `ActiveSupport::Notification`s at various points during job and worker
lifecycles, and can also be configured for continuious monitoring. You are strongly encouraged to
tie these up to your preferred application monitoring solution by calling
`ActiveSupport::Notification.subscribe` in an initializer.

### Lifecycle Hooks

The following events will be emitted automatically by workers as jobs are reserved and performed:

- **delayed.job.run** - an event measuring the duration of a job's execution
- **delayed.job.error** - an event indicating that a job has errored and may be retried (no duration attached)
- **delayed.job.failure** - an event indicating that a job has permanently failed (no duration attached)
- **delayed.job.enqueue** - an event measuring the time it takes to enqueue a job
- **delayed.worker.reserve_jobs** - an event measuring the duration of the job "pickup query"

The "run", "error", "failure" and "enqueue" events will include a `:job` argument in the event's payload,
providing access to the job instance.

```ruby
ActiveSupport::Notifications.subscribe('delayed.job.run') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  # Emit the event via your preferred metrics/instrumentation provider:
  tags = event.payload.except(:job).map { |k,v| "#{k.to_s[0..64]}:#{v.to_s[0..255]}" }
  StatsD.distribution(event.name, event.duration, tags: tags)
end

ActiveSupport::Notifications.subscribe(/delayed\.job\.(error|failure)/) do |*args|
  # ...
  Statsd.increment(...)
end

ActiveSupport::Notifications.subscribe('delayed.job.enqueue') do |*args|
  # ...
  StatsD.distribution(...)
end

ActiveSupport::Notifications.subscribe('delayed.worker.reserve_jobs') do |*args|
  # ...
  StatsD.distribution(...)
end
```

### Priority-based Alerting Threshholds

By default, jobs support "alerting threshholds" that allow them to warn if they
come within range of `max_run_time` or `max_attempts` (without exceeding them),
or if they spend too long waiting in the queue (i.e. their "age").

The threshholds are fully configurable, and default to the following values:

```ruby
Delayed::Priority.alerts = {
  interactive: { age: 1.minute, run_time: 30.seconds, attempts: 3 },
  user_visible: { age: 3.minutes, run_time: 90.seconds, attempts: 5 },
  eventual: { age: 1.5.hours, run_time: 5.minutes, attempts: 8 },
  reporting: { age: 4.hours, run_time: 10.minutes, attempts: 8 },
}
```

These may also be configured on a per-job basis:

```ruby
class MyVeryHighThroughputJob < ApplicationJob
  # ...

  def alert_run_time
    5.seconds # must execute in under 5 seconds
  end

  def alert_attempts
    1 # will begin alerting after 1 attempt
  end
end
```

If a job completes but was uncomfortably close to timing-out, it may make sense
to emit an alert:

```ruby
ActiveSupport::Notifications.subscribe('delayed.job.run') do |_name, _start, _finish, _id, payload|
  job = payload[:job]
  TeamAlerter.alert!("Job with ID #{job.id} took #{job.run_time} seconds to run") if job.run_time_alert?
end
```

Similarly, if a job is erroring repeatedly, you may choose to emit some form of
notification before it reaches its full attempt count:

```ruby
ActiveSupport::Notifications.subscribe('delayed.job.error') do |_name, _start, _finish, _id, payload|
  job = payload[:job]
  TeamAlerter.alert!("Job with ID #{job.id} has made #{job.attempts} attempts") if job.attempts_alert?
end
```

The last threshhold (`job.age_alert?`) refers to the time spent in the queue,
and may be best monitored in aggregate (covered in the next section!), as it
generally describes the ability of workers to pick up jobs fast enough.

### Continuous Monitoring

To continuously monitor the state of your job queues, you may run a single "monitor" process
alongside your workers.  (Only one instance of this process is needed, as it will emit aggregate
metrics.)

```
rake delayed:monitor
```

The monitor process accepts the same queue configurations as the worker process, and can be used to
monitor the same sets of queues as the workers:

```bash
QUEUE=tracking rake delayed:monitor
QUEUES=mailers,tasks rake delayed:monitor
```

The following events will be emitted, grouped by priority name (e.g. "interactive") and queue name,
and the metric's "`:value`" will be available in the event's payload.  **This means that there will
be one value _per_ unique combination of queue & priority**, and totals must be computed via
downstream aggregation (e.g. as a StatsD "gauge" metric).

- **delayed.job.count** - the total number of jobs
- **delayed.job.future_count** - jobs where run_at is in the future
- **delayed.job.working_count** - jobs that are currently being worked off (excludes failed jobs)
- **delayed.job.workable_count** - jobs that are waiting to be worked off
- **delayed.job.erroring_count** - jobs where attempts > 0
- **delayed.job.failed_count** - jobs where failed_at is not nil
- **delayed.job.max_lock_age** - the age of the oldest locked_at value (excludes failed jobs)
- **delayed.job.max_age** - the age of the oldest run_at value (excludes failed jobs)

An additional _experimental_ metric is available, intended for use with application autoscaling:

- **delayed.job.alert_age_percent** - the _percent_ to which the oldest job has reached the "age alert" threshold. (See the [Alerting Threshholds](#priority-based-alerting-threshholds) section above.)

All of these events may be subscribed to via a single regular expression (again, in your application
config or in an initializer):

```ruby
ActiveSupport::Notifications.subscribe(/delayed\.job\..*_(count|age|percent)/) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  value = event.payload.delete(:value)

  # Emit the event via your preferred metrics/instrumentation provider:
  tags = event.payload.map { |k,v| "#{k.to_s[0..64]}:#{v.to_s[0..255]}" }
  StatsD.gauge(event.name, value, sample_rate: 1.0, tags: tags)
end
```

Additionally, the monitor process with emit a **delayed.monitor.run** event with a duration
attached, so that you can monitor the time it takes to emit these aggregate metrics.

```ruby
ActiveSupport::Notifications.subscribe('delayed.monitor.run') do |*args|
  # ...
  StatsD.distribution(...)
end
```

## Configuration

`Delayed` is highly configurable, but ships with opinionated defaults.  If you need to change any
default behaviors, you can do so in an initializer (e.g. `config/initializers/delayed.rb`).

By default, workers will claim 5 jobs at a time (run in concurrent threads). If no jobs are found,
workers will sleep for 5 seconds.

```ruby
# The max number of jobs a worker may lock at a time (also the size of the thread pool):
Delayed::Worker.max_claims = 5

# The number of jobs to which a worker may "read ahead" when locking jobs (mysql only!):
Delayed::Worker.read_ahead = 5

# If a worker finds no jobs, it will sleep this number of seconds in between attempts:
Delayed::Worker.sleep_delay = 5
```

If a job fails, it will be rerun up to 25 times (with an exponential back-off). Jobs will also
time-out after 20 minutes.

```ruby
# The max number of attempts jobs are given before they are permanently marked as failed:
Delayed::Worker.max_attempts = 25

# The max amount of time a job is allowed to run before it is stopped:
Delayed::Worker.max_run_time = 20.minutes
```

Individual jobs may specify their own `max_attempts` and `max_run_time`:

```ruby
class MyJob < ApplicationJob
  def perform; end

  def max_run_time
    15.minutes # must be less than the global `max_run_time` default!
  end

  def max_attempts
    1
  end
end
```

By default, workers will work off all queues (including `nil`), and jobs will be enqueued to a
`'default'` queue.

```ruby
# A list of queues to which all work is restricted. (e.g. `%w(queue1 queue2 queue3)`)
# If no queues are specified, then all queues will be worked off
Delayed::Worker.queues = []

# The default queue that jobs will be enqueued to, when no other queue is specified:
Delayed::Worker.default_queue_name = 'default'
```

Priority ranges are given names. These will default to "interactive" for 0-9, "user visible" for
10-19, "eventual" for 20-29, and "reporting" for 30+. The default priority for enqueued jobs is
"user visible" (10), and workers will work off all priorities, unless otherwise configured.

```ruby
# Default priority names, useful for enqueuing and for instrumentation/metrics.
Delayed::Priority.names = { interactive: 0, user_visible: 10, eventual: 20, reporting: 30 }

# The default priority for enqueued jobs, when no priority is specified.
# This aligns with the "user_visible" named priority.
Delayed::Worker.default_priority = 10

# A worker can also be told to work off specific priority ranges,
# if, say, you'd like a dedicated worker for high priority jobs:
Delayed::Worker.min_priority = nil
Delayed::Worker.max_priority = nil
```

Logging verbosity is also configurable. The gem will attempt to default to `Rails.logger` with an
"info" log level.

```ruby
# Specify an alternate logger class:
Delayed.logger = Rails.logger

# Specify a default log level for all job lifecycle logging:
Delayed.default_log_level = 'info'
```

## Migrating from other ActiveJob backends

For the most part, standard ActiveJob APIs should be fully compatible. However, when migrating from
a Redis-backed queue (or some other queue that is not co-located with your ActiveRecord data), the
[Operational Considerations](#operational-considerations) section of this README should be noted.
You may wish to change the way that jobs are enqueued and executed in order to benefit from
co-transactional / ACID guarantees.

To assist in migrating, you are encouraged to set `queue_adapter` on a per-job basis, so that you
can move and monitor fewer job classes at a time:

```ruby
class NewsletterJob < ApplicationJob
  self.queue_adapter = :sidekiq
end

class OrderPurchaseJob < ApplicationJob
  self.queue_adapter = :delayed
end
```

#### Migrating from DelayedJob

If you choose to use `delayed` in an app that was originally written against `delayed_job`, several
non-ActiveJob APIs are still available. These include "plugins", lifecycle hooks, and the `.delay`
and `.handle_asynchronously` methods. **These APIs are intended to assist in migrating older
codebases onto `ActiveJob`**, and may eventually be removed or extracted into an optional gem.

For comprehensive information on the APIs and features that `delayed` has inherited from
`delayed_job` and `delayed_job_active_record`, refer to [DelayedJob's
documentation](https://github.com/collectiveidea/delayed_job).

When migrating from `delayed_job`, you may choose to manually apply its default configurations:

```ruby
Delayed::Worker.max_run_time = 4.hours
Delayed::Worker.default_priority = 0
Delayed::Worker.default_queue_name = nil
Delayed::Worker.destroy_failed_jobs = true # WARNING: This will irreversably delete jobs.
```

Note that some configurations, like `queue_attributes`, `exit_on_complete`, `backend`, and
`raise_signal_exceptions` have been removed entirely.

## How to Contribute

We would love for you to contribute! Anything that benefits the majority of users—from a
documentation fix to an entirely new feature—is encouraged.

Before diving in, [check our issue tracker](//github.com/Betterment/delayed/issues) and consider
creating a new issue to get early feedback on your proposed change.

### Suggested Workflow

* Fork the project and create a new branch for your contribution.
* Write your contribution (and any applicable test coverage).
* Make sure all tests pass (`bundle exec rake`).
* Submit a pull request.
