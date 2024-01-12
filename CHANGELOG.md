# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project aims to adhere to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added <!-- for new features. -->
### Changed <!-- for changes in existing functionality. -->
### Deprecated <!-- for soon-to-be removed features. -->
### Removed <!-- for now removed features. -->
### Fixed <!-- for any bug fixes. -->

- Bring ActiveJob queue adapter's enqueuing behaviour inline with delayed_job &
  upstream adapters, by stopping it serializing & deserializing the job instance
  during the enqueue process.

## [0.5.0] - 2023-01-20
### Changed
- Reduced handler size by excluding redundant 'job:' key (only 'job_data:' is
  necessary). This ensures that a job can be deserialized even if the underlying
  ActiveJob class is unknown to the worker, and will result in a retryable
  `NameError` instead of a permanently-failed `DeserializationError`.

## [0.4.0] - 2021-11-30
### Fixed
- Fix Ruby 3.0 kwarg compatibility issue when executing jobs enqueued via the
  `Delayed::MessageSending` APIs (`.delay` and `handle_asynchronously`).
### Changed
- `Delayed::PerformableMethod` now splits `kwargs` out into a separate attribute, while still being
  backwards-compatible with jobs enqueued via the previous gem version. This is an undocumented
  internal API and is not considered a breaking change, but if you had previously relied on
  `payload_object.args.last` to access keyword arguments, you must now use `payload_object.kwargs`.

## [0.3.0] - 2021-10-26
### Added
- Add more official support for Rails 7.0 (currently alpha2). There were no gem conflicts, but this
  adds an entry to our `Appraisals` file so that we run CI tests against ActiveRecord 7.
### Fixed
- Fix Rails 7.0 deprecation warnings caused by usages of `ActiveRecord::Base.default_timestamp`
- Fix tests that relied on classic autoloader behavior. Now we pull in Zeitwerk where necessary.
- Fix a couple issues caught by the linter, most notably resulting in a switch from `IO.select(...)`
  to `IO#wait_readable(...)`, improving support for Ruby 3 scheduler hooks.

## [0.2.0] - 2021-08-30
### Fixed
- Fix the loading of `Delayed::Job` constant on newly-generated Rails 6.1 apps. (previously, the
  constant would not be available until `ActiveRecord::Base` was referenced for the first time)
### Changed
- The `Delayed::Railtie` is now a `Delayed::Engine`, allowing it to autoload constants via Rails'
  built-in autoloader. In a non-Rails context, `require 'delayed'` will eager-load its models.

## [0.1.1] - 2021-08-19
### Added
- This CHANGELOG file!
### Fixed
- Fix the gemspec description, which had previously been written in rdoc format (causing it to
  appear garbled on rubygems.org).

## [0.1.0] - 2021-08-17
### Added
- Initial release! This repo is the result of some merging, squashing, and commit massaging, in
  preparation for a public release! The goal was to maintain historical commit authorship of the
  ancestor repos (`delayed_job` and `delayed_job_active_record`), plus the changes from Betterment's
  internal forks.

[0.5.0]: https://github.com/betterment/delayed/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/betterment/delayed/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/betterment/delayed/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/betterment/delayed/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/betterment/delayed/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/betterment/delayed/releases/tag/v0.1.0
