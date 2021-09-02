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

[0.2.0]: https://github.com/betterment/delayed/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/betterment/delayed/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/betterment/delayed/releases/tag/v0.1.0
