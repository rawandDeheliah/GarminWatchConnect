// =============================================================
// TestingApplicationApp.mc
// watch-app + Background temporal event to keep SensorLogger
// alive even when the app is not on screen
// =============================================================

import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.SensorLogging;
import Toybox.System;

class TestingApplicationApp extends Application.AppBase {

    var _logger = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Start SensorLogger immediately when app launches
        _startLogger();

        // Register background temporal event every 5 minutes
        // This keeps the app process alive in background
        Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        System.println("[APP] Background temporal event registered (5 min)");
    }

    function onStop(state as Dictionary?) as Void {
        _logger = null;
        System.println("[APP] App stopped");
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new TestingApplicationView();
        var delegate = new TestingApplicationDelegate(view);
        return [ view, delegate ];
    }

    // Called every 5 minutes in background
    function getServiceDelegate() {
        return [new TestingApplicationServiceDelegate()];
    }

    function _startLogger() {
        try {
            _logger = new SensorLogging.SensorLogger({
                :accelerometer => { :enabled => true },
                :gyroscope     => { :enabled => true }
            });
            System.println("[LOGGER] Recording accel + gyro to FIT");
        } catch (ex instanceof Lang.Exception) {
            System.println("[LOGGER] SensorLogging not available");
        }
    }

}

function getApp() as TestingApplicationApp {
    return Application.getApp() as TestingApplicationApp;
}
