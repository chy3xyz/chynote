Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });

const browser = require('@sentry/core/browser');
const debugBuild = require('../debug-build.js');
const helpers = require('../helpers.js');

/**
 * Add a listener that cancels and finishes a transaction when the global
 * document is hidden.
 */
function registerBackgroundTabDetection() {
  if (helpers.WINDOW.document) {
    helpers.WINDOW.document.addEventListener('visibilitychange', () => {
      const activeSpan = browser.getActiveSpan();
      if (!activeSpan) {
        return;
      }

      const rootSpan = browser.getRootSpan(activeSpan);

      if (helpers.WINDOW.document.hidden && rootSpan) {
        const cancelledStatus = 'cancelled';

        const { op, status } = browser.spanToJSON(rootSpan);

        if (debugBuild.DEBUG_BUILD) {
          browser.debug.log(`[Tracing] Transaction: ${cancelledStatus} -> since tab moved to the background, op: ${op}`);
        }

        // We should not set status if it is already set, this prevent important statuses like
        // error or data loss from being overwritten on transaction.
        if (!status) {
          rootSpan.setStatus({ code: browser.SPAN_STATUS_ERROR, message: cancelledStatus });
        }

        rootSpan.setAttribute('sentry.cancellation_reason', 'document.hidden');
        rootSpan.end();
      }
    });
  } else {
    debugBuild.DEBUG_BUILD && browser.debug.warn('[Tracing] Could not set up background tab detection due to lack of global document');
  }
}

exports.registerBackgroundTabDetection = registerBackgroundTabDetection;
//# sourceMappingURL=backgroundtab.js.map
