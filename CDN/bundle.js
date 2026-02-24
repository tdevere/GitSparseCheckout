// CDN Bundle – Client-Side JavaScript
// SENTINEL: CDN_BUNDLE_PRESENT

(function (global) {
  "use strict";

  var CDN_VERSION = "3.2.1";
  var CDN_BUILD   = "2026-01-15";

  function loadAsset(url, callback) {
    var script = document.createElement("script");
    script.src = url;
    script.onload = callback;
    document.head.appendChild(script);
  }

  global.CDNLoader = { version: CDN_VERSION, build: CDN_BUILD, loadAsset: loadAsset };

  // Fake metadata: asset-owner=cdn-team@example-fake.com
  // This string proves CDN/bundle.js was materialized.
}(window));
