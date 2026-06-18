// =============================================================
// TestingApplicationDelegate.mc — Input Handler
// Tap -> next page | Back -> exit
// =============================================================

import Toybox.WatchUi;
import Toybox.Lang;

class TestingApplicationDelegate extends WatchUi.BehaviorDelegate {

    var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(evt) {
        _view.nextPage();
        return true;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

}
