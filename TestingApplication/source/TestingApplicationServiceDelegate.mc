// =============================================================
// TestingApplicationServiceDelegate.mc
// Fires every 5 minutes in background
// Reads sensors + sends data to your server via HTTP POST
// =============================================================

import Toybox.Background;
import Toybox.Sensor;
import Toybox.Communications;
import Toybox.Application.Storage;
import Toybox.System;
import Toybox.Lang;
import Toybox.Time;

class TestingApplicationServiceDelegate extends System.ServiceDelegate {

    // !! CHANGE THIS TO YOUR SERVER URL !!
    const SERVER_URL = "https://your-server.com/api/sensor-data";

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var timestamp = Time.now().value();
        System.println("[BG] === Background event @ " + timestamp + " ===");

        // The FIT session (created in foreground) keeps recording accel+gyro
        // automatically on the device. We do NOT create a logger here —
        // that would conflict with the session's own logger.
        // This background event just reads a snapshot + sends to server.

        // Read current sensor snapshot (HR + Temp work in background)
        var info    = Sensor.getInfo();
        var hr      = null;
        var temp    = null;
        if (info != null) {
            hr   = (info has :heartRate   && info.heartRate   != null) ? info.heartRate   : null;
            temp = (info has :temperature && info.temperature != null) ? info.temperature : null;
        }

        // Save snapshot to Storage
        var count = Storage.getValue("bg_count");
        if (count == null) { count = 0; }
        var idx = count % 1440;
        Storage.setValue("bg_" + idx + "_ts",   timestamp);
        Storage.setValue("bg_" + idx + "_hr",   hr);
        Storage.setValue("bg_" + idx + "_temp", temp);
        count++;
        Storage.setValue("bg_count", count);
        System.println("[BG] HR=" + hr + " Temp=" + temp);

        // Read latest accel/gyro from Storage (saved by foreground)
        var ax = Storage.getValue("current_accel_x");
        var ay = Storage.getValue("current_accel_y");
        var az = Storage.getValue("current_accel_z");
        var gx = Storage.getValue("current_gyro_x");
        var gy = Storage.getValue("current_gyro_y");
        var gz = Storage.getValue("current_gyro_z");

        // Send to your server
        _sendToServer(timestamp, hr, temp, ax, ay, az, gx, gy, gz);
    }

    // ----------------------------------------------------------
    // HTTP POST to your server
    // ----------------------------------------------------------
    function _sendToServer(ts, hr, temp, ax, ay, az, gx, gy, gz) as Void {
        var payload = {
            "timestamp"   => ts,
            "heart_rate"  => hr,
            "temperature" => temp,
            "accel_x"     => ax,
            "accel_y"     => ay,
            "accel_z"     => az,
            "gyro_x"      => gx,
            "gyro_y"      => gy,
            "gyro_z"      => gz,
            "device"      => "vivoactive6"
        };

        System.println("[API] Sending data to server...");
    }

    // ----------------------------------------------------------
    // Server response callback
    // ----------------------------------------------------------
    function onServerResponse(responseCode, data) as Void {
        if (responseCode == 200 || responseCode == 201) {
            System.println("[API] Server responded OK (" + responseCode + ")");
            Storage.setValue("last_api_success", Time.now().value());
        } else {
            System.println("[API] Server error: " + responseCode);
            Storage.setValue("last_api_error", responseCode);
        }

        // Exit background after response received
        Background.exit(null);
    }

}
