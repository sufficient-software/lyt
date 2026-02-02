/**
 * Lyt Analytics JavaScript SDK
 *
 * A lightweight analytics tracker for Phoenix applications.
 * Events are queued locally and sent in batches to reduce network requests.
 *
 * Usage (script tag):
 *   <script defer data-api="/api/analytics" src="/js/lyt.js"></script>
 *
 * Usage (manual):
 *   lyt('Page View', { path: '/home' })
 *   lyt('Button Click', { metadata: { button_id: 'signup' } })
 *
 * Configuration (data attributes on script tag):
 *   data-api        - API endpoint (default: "/api/analytics")
 *   data-auto       - Auto-track pageviews: "true" or "false" (default: "true")
 *   data-hash       - Track hash changes: "true" or "false" (default: "false")
 *   data-spa        - SPA mode (track history changes): "true" or "false" (default: "true")
 *   data-interval   - Flush interval in ms (default: "1000")
 */
(function () {
  "use strict";

  // Configuration
  var config = {
    endpoint: "/api/analytics",
    autoPageview: true,
    hashRouting: false,
    spaMode: true,
    flushInterval: 1000,
    debug: false,
  };

  // Event queue
  var eventQueue = [];
  var flushTimer = null;
  var lastPath = null;
  var initialized = false;

  /**
   * Get configuration from script tag data attributes
   */
  function getScriptConfig() {
    var scripts = document.getElementsByTagName("script");
    for (var i = 0; i < scripts.length; i++) {
      var script = scripts[i];
      if (script.src && script.src.indexOf("lyt") !== -1) {
        if (script.dataset.api) {
          config.endpoint = script.dataset.api;
        }
        if (script.dataset.auto === "false") {
          config.autoPageview = false;
        }
        if (script.dataset.hash === "true") {
          config.hashRouting = true;
        }
        if (script.dataset.spa === "false") {
          config.spaMode = false;
        }
        if (script.dataset.interval) {
          config.flushInterval = parseInt(script.dataset.interval, 10) || 1000;
        }
        if (script.dataset.debug === "true") {
          config.debug = true;
        }
        break;
      }
    }
  }

  /**
   * Log debug messages
   */
  function debug(message, data) {
    if (config.debug && console && console.log) {
      console.log("[Lyt]", message, data || "");
    }
  }

  /**
   * Check if we should track (filter out bots, local files, etc.)
   */
  function shouldTrack() {
    // Don't track local files
    if (location.protocol === "file:") {
      debug("Skipping: file protocol");
      return false;
    }

    // Don't track if automated testing detected
    if (
      window._phantom ||
      window.__nightmare ||
      window.navigator.webdriver ||
      window.Cypress
    ) {
      debug("Skipping: automation detected");
      return false;
    }

    // Check for opt-out flag
    try {
      if (window.localStorage && window.localStorage.lyt_ignore === "true") {
        debug("Skipping: localStorage opt-out");
        return false;
      }
    } catch (e) {
      // localStorage not available
    }

    return true;
  }

  /**
   * Build event payload
   */
  function buildPayload(name, options) {
    options = options || {};

    var payload = {
      name: name,
      path: options.path || location.pathname,
      hostname: options.hostname || location.hostname,
      query: options.query || location.search.substring(1),
    };

    // Add metadata if provided
    if (options.metadata) {
      payload.metadata = options.metadata;
    }

    // Add screen dimensions and UTM params on first event
    if (!initialized) {
      payload.screen_width =
        window.innerWidth || document.documentElement.clientWidth;
      payload.screen_height =
        window.innerHeight || document.documentElement.clientHeight;

      // Add UTM parameters if present in URL
      var params = new URLSearchParams(location.search);
      if (params.get("utm_source"))
        payload.utm_source = params.get("utm_source");
      if (params.get("utm_medium"))
        payload.utm_medium = params.get("utm_medium");
      if (params.get("utm_campaign"))
        payload.utm_campaign = params.get("utm_campaign");
      if (params.get("utm_term")) payload.utm_term = params.get("utm_term");
      if (params.get("utm_content"))
        payload.utm_content = params.get("utm_content");

      initialized = true;
    }

    return payload;
  }

  /**
   * Add event to queue and schedule flush
   */
  function queueEvent(name, options, callback) {
    if (!shouldTrack()) {
      if (callback) callback({ ignored: true });
      return;
    }

    var payload = buildPayload(name, options);

    eventQueue.push({
      payload: payload,
      callback: callback,
    });

    debug("Queued event:", payload);

    // Schedule flush if not already scheduled
    scheduleFlush();
  }

  /**
   * Schedule a flush of the event queue
   */
  function scheduleFlush() {
    if (flushTimer) return;

    flushTimer = setTimeout(function () {
      flushTimer = null;
      flush();
    }, config.flushInterval);
  }

  /**
   * Flush all queued events to the server
   */
  function flush(callback) {
    if (eventQueue.length === 0) {
      debug("Queue empty, nothing to flush");
      if (callback) callback({ ok: true, queued: 0 });
      return;
    }

    // Grab current queue and reset
    var toSend = eventQueue.slice();
    var callbacks = toSend
      .map(function (item) {
        return item.callback;
      })
      .filter(Boolean);
    eventQueue = [];

    // Clear any pending timer
    if (flushTimer) {
      clearTimeout(flushTimer);
      flushTimer = null;
    }

    var events = toSend.map(function (item) {
      return item.payload;
    });

    debug("Flushing " + events.length + " events");

    var url = config.endpoint + "/events";

    // Use fetch with keepalive for reliability
    if (window.fetch) {
      fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        keepalive: true,
        body: JSON.stringify({ events: events }),
      })
        .then(function (response) {
          return response.json();
        })
        .then(function (data) {
          debug("Flush complete:", data);
          // Call all individual callbacks
          callbacks.forEach(function (cb) {
            cb(data);
          });
          if (callback) callback(data);
        })
        .catch(function (error) {
          debug("Flush error:", error);
          var errorResponse = { error: error };
          callbacks.forEach(function (cb) {
            cb(errorResponse);
          });
          if (callback) callback(errorResponse);
        });
    } else {
      // Fallback to XMLHttpRequest for older browsers
      var xhr = new XMLHttpRequest();
      xhr.open("POST", url, true);
      xhr.setRequestHeader("Content-Type", "application/json");
      xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
          var response;
          if (xhr.status >= 200 && xhr.status < 300) {
            try {
              response = JSON.parse(xhr.responseText);
            } catch (e) {
              response = { ok: true };
            }
            debug("Flush complete:", response);
          } else {
            response = { error: xhr.status };
            debug("Flush error:", xhr.status);
          }
          callbacks.forEach(function (cb) {
            cb(response);
          });
          if (callback) callback(response);
        }
      };
      xhr.send(JSON.stringify({ events: events }));
    }
  }

  /**
   * Track a pageview
   */
  function trackPageview(options) {
    var currentPath = config.hashRouting
      ? location.pathname + location.hash
      : location.pathname;

    // Avoid duplicate pageviews for same path
    if (options && options.checkDuplicate && lastPath === currentPath) {
      debug("Skipping duplicate pageview:", currentPath);
      return;
    }

    lastPath = currentPath;
    queueEvent("Page View", options);
  }

  /**
   * Set up automatic pageview tracking
   */
  function setupAutoPageview() {
    if (!config.autoPageview) {
      debug("Auto pageview disabled");
      return;
    }

    // Track SPA navigation via History API
    if (config.spaMode && window.history && window.history.pushState) {
      var originalPushState = history.pushState;
      history.pushState = function () {
        originalPushState.apply(this, arguments);
        trackPageview({ checkDuplicate: true });
      };

      window.addEventListener("popstate", function () {
        trackPageview({ checkDuplicate: true });
      });
    }

    // Track hash changes if enabled
    if (config.hashRouting) {
      window.addEventListener("hashchange", function () {
        trackPageview({ checkDuplicate: true });
      });
    }

    // Handle visibility changes (track when page becomes visible)
    function handleVisibilityChange() {
      if (document.visibilityState === "visible" && lastPath === null) {
        trackPageview();
      }
    }

    // Handle initial pageview
    if (document.visibilityState === "visible") {
      trackPageview();
    } else {
      document.addEventListener("visibilitychange", handleVisibilityChange);
    }

    // Handle browser back/forward cache
    window.addEventListener("pageshow", function (event) {
      if (event.persisted) {
        trackPageview();
      }
    });
  }

  /**
   * Flush queue before page unload
   */
  function setupBeforeUnload() {
    // Use pagehide for mobile Safari compatibility
    window.addEventListener("pagehide", function () {
      if (eventQueue.length > 0) {
        flush();
      }
    });

    // Also listen to visibilitychange for when tab is hidden
    document.addEventListener("visibilitychange", function () {
      if (document.visibilityState === "hidden" && eventQueue.length > 0) {
        flush();
      }
    });
  }

  /**
   * Main tracking function
   *
   * Usage:
   *   lyt('Event Name')
   *   lyt('Event Name', { metadata: { key: 'value' } })
   *   lyt('Event Name', { path: '/custom-path' })
   *   lyt('Event Name', { metadata: {...} }, callback)
   */
  function lyt(eventName, options, callback) {
    // Handle case where options is actually the callback
    if (typeof options === "function") {
      callback = options;
      options = {};
    }

    queueEvent(eventName, options, callback);
  }

  /**
   * Flush the event queue immediately
   *
   * Usage:
   *   lyt.flush(function(response) { console.log('Flushed:', response.queued) })
   */
  lyt.flush = function (callback) {
    flush(callback);
  };

  /**
   * Manual pageview tracking
   *
   * Usage:
   *   lyt.pageview()
   *   lyt.pageview({ path: '/virtual-page' })
   */
  lyt.pageview = function (options) {
    trackPageview(options);
  };

  /**
   * Configure the tracker
   *
   * Usage:
   *   lyt.configure({ endpoint: '/custom/api', debug: true })
   */
  lyt.configure = function (options) {
    if (options.endpoint) config.endpoint = options.endpoint;
    if (options.autoPageview !== undefined)
      config.autoPageview = options.autoPageview;
    if (options.hashRouting !== undefined)
      config.hashRouting = options.hashRouting;
    if (options.spaMode !== undefined) config.spaMode = options.spaMode;
    if (options.flushInterval !== undefined)
      config.flushInterval = options.flushInterval;
    if (options.debug !== undefined) config.debug = options.debug;
    debug("Configuration updated:", config);
  };

  /**
   * Get current queue length (useful for debugging)
   */
  lyt.queueLength = function () {
    return eventQueue.length;
  };

  /**
   * Opt out of tracking (persists to localStorage)
   */
  lyt.optOut = function () {
    try {
      if (window.localStorage) {
        window.localStorage.lyt_ignore = "true";
        debug("Opted out of tracking");
      }
    } catch (e) {
      debug("Could not set opt-out flag");
    }
  };

  /**
   * Opt back in to tracking
   */
  lyt.optIn = function () {
    try {
      if (window.localStorage) {
        delete window.localStorage.lyt_ignore;
        debug("Opted in to tracking");
      }
    } catch (e) {
      debug("Could not remove opt-out flag");
    }
  };

  // Version
  lyt.version = "0.1.0";

  // Process any queued events from before script loaded
  var queue = window.lyt && window.lyt.q;
  if (queue && Array.isArray(queue)) {
    for (var i = 0; i < queue.length; i++) {
      lyt.apply(null, queue[i]);
    }
  }

  // Initialize
  getScriptConfig();
  setupAutoPageview();
  setupBeforeUnload();

  // Expose globally
  window.lyt = lyt;
})();
