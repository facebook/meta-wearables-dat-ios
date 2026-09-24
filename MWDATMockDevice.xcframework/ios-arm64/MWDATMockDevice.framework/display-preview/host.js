/**
 * (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
 */

(() => {
  'use strict';

  const readyAttribute = 'data-dat-preview-ready';
  const readyEvent = 'dat-preview-ready';
  const clickEvent = 'dat-preview-click';
  const videoPlaybackEvent = 'dat-preview-video-playback';
  const pollIntervalMs = 250;
  const initialRetryMs = 500;
  const maximumRetryMs = 4000;

  let revision = null;
  let retryMs = initialRetryMs;
  let started = false;
  let stopped = false;

  function postJSON(path, body) {
    return fetch(path, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(body),
      cache: 'no-store',
      credentials: 'omit',
    });
  }

  async function updateGuidanceTitle() {
    try {
      const response = await fetch('/display/config', {
        cache: 'no-store',
        credentials: 'omit',
      });
      if (!response.ok) {
        return;
      }
      const config = await response.json();
      if (typeof config.appName !== 'string' || config.appName.length === 0) {
        return;
      }
      const title = document.getElementById('extension-guidance-title');
      if (title) {
        title.textContent = `Preview ${config.appName} in Chrome`;
      }
    } catch {}
  }

  async function poll() {
    while (!stopped) {
      let delayMs = pollIntervalMs;
      try {
        const previousRevision = revision;
        const response = await postJSON('/display/content', {
          afterRevision: revision,
        });
        if (response.status !== 204) {
          if (!response.ok) {
            throw new Error('DAT preview content request failed');
          }
          const content = await response.json();
          if (
            !Number.isSafeInteger(content.revision) ||
            content.revision < 1 ||
            (typeof content.payload !== 'string' && content.payload !== null)
          ) {
            throw new Error('Invalid DAT preview content response');
          }
          if (
            previousRevision !== null &&
            content.revision <= previousRevision
          ) {
            window.location.reload();
            return;
          }
          revision = content.revision;
          window.postMessage(content.payload ?? '', window.location.origin);
        }
        retryMs = initialRetryMs;
      } catch {
        delayMs = retryMs;
        retryMs = Math.min(retryMs * 2, maximumRetryMs);
      }
      await new Promise(resolve => window.setTimeout(resolve, delayMs));
    }
  }

  function handleClick(event) {
    const identifier = event.detail;
    if (
      typeof identifier !== 'string' ||
      identifier.length === 0 ||
      identifier.length > 256
    ) {
      return;
    }
    postJSON('/display/click', {identifier}).catch(() => {});
  }

  function handleVideoPlayback(event) {
    const playbackEvent = event.detail;
    if (
      playbackEvent !== 'started' &&
      playbackEvent !== 'stopped' &&
      playbackEvent !== 'ended'
    ) {
      return;
    }
    postJSON('/display/video', {event: playbackEvent}).catch(() => {});
  }

  function start() {
    if (started || stopped) {
      return;
    }
    started = true;
    window.addEventListener(clickEvent, handleClick);
    window.addEventListener(videoPlaybackEvent, handleVideoPlayback);
    void updateGuidanceTitle();
    void poll();
  }

  window.addEventListener('pagehide', () => {
    stopped = true;
    window.removeEventListener(clickEvent, handleClick);
    window.removeEventListener(videoPlaybackEvent, handleVideoPlayback);
  });

  if (document.documentElement.getAttribute(readyAttribute) === 'true') {
    start();
  } else {
    window.addEventListener(readyEvent, start, {once: true});
  }
})();
