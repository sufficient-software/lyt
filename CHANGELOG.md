# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-XX

### Added

- Initial release of PhxAnalytics
- **Core Features**
  - Automatic LiveView mount and navigation tracking via telemetry
  - Page view tracking for non-LiveView requests via Plug
  - Custom event tracking with `@analytics` decorator
  - Session management with automatic ID generation
  
- **Session Tracking**
  - Browser and OS detection via UAInspector
  - UTM parameter capture (source, medium, campaign, term, content)
  - Custom metadata support
  - Session upsert behavior for updates
  
- **Event Tracking**
  - Automatic parameter capture in event metadata
  - Custom event names and metadata
  - Dynamic metadata via functions
  - `before_save` callbacks for filtering/modification
  
- **Module-Level Configuration**
  - `track_all` option to track all handle_event calls
  - `include` list to track specific events without decorator
  - `exclude` list to skip certain events
  - Module-level `before_save` callback
  
- **Performance**
  - Async event queuing via GenServer
  - Configurable batch size and flush interval
  - Session dependency ordering (sessions inserted before events)
  - Synchronous mode for testing
  
- **Database Support**
  - PostgreSQL adapter support
  - MySQL adapter support
  - SQLite3 adapter support
  - Automatic adapter detection
  - Internal migration versioning system
  
- **Configuration**
  - Configurable session cookie name
  - Configurable session length
  - Path exclusion list
  - EventQueue tuning options
