// =============================================================
// TestingApplicationServiceDelegate.mc
// Runs every 5 minutes in background to keep logger alive
// =============================================================

import Toybox.Background;
import Toybox.SensorLogging;
import Toybox.System;
import Toybox.Lang;

class TestingApplicationServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    // Fires every 5 minutes even when app is not on screen
    function onTemporalEvent() as Void {
        System.println("[BG] Background event fired — logger still running");

        // Read a quick snapshot via Sensor.getInfo()
        var info = Sensor.getInfo();
        if (info != null) {
            System.println("[BG] HR: " + info.heartRate);
            System.println("[BG] Temp: " + info.temperature);
        }

        // SensorLogger continues recording automatically
        // No need to restart it — Garmin keeps it running
        Background.exit(null);
    }

}
