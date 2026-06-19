// =============================================================
// TestingApplicationDelegate.mc — Input Handler
// Tap  -> next page
// Back -> exit app (final FIT save happens in onStop)
// =============================================================

import Toybox.WatchUi;
import Toybox.Lang;

class TestingApplicationDelegate extends WatchUi.BehaviorDelegate {

    var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Tap -> next display page
    function onTap(evt) {
        _view.nextPage();
        return true;
    }

    // Back -> exit app
    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

}
