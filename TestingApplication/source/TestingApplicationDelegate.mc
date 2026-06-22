// =============================================================
// TestingApplicationDelegate.mc — Input Handler
//
// While recording:
//   - Back button is BLOCKED (return true) so the app never exits
//     accidentally. The app keeps running with the screen off and
//     keeps recording accel/gyro to the FIT file.
//   - Tap switches display pages.
//   - To actually stop + save: press back 3 times within 3 seconds.
// =============================================================

import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Timer;

class TestingApplicationDelegate extends WatchUi.BehaviorDelegate {

    var _view;
    var _backCount = 0;
    var _backTimer = null;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Tap -> next display page
    function onTap(evt) {
        _view.nextPage();
        return true;
    }

    // Back button -> blocked while recording.
    // Press 3x within 3 seconds to actually stop + exit.
    function onBack() {
        _backCount++;

        if (_backTimer == null) {
            _backTimer = new Timer.Timer();
        }
        _backTimer.stop();
        _backTimer.start(method(:resetBackCount), 3000, false);

        if (_backCount >= 3) {
            // User really wants to stop — save and exit
            _view.confirmExit();
            return false;  // allow app to close (onStop saves)
        }

        // Show "press back 3x to stop" hint and stay in app
        _view.showBackHint(_backCount);
        return true;  // block exit — recording continues
    }

    function resetBackCount() as Void {
        _backCount = 0;
        _view.showBackHint(0);
    }

}
