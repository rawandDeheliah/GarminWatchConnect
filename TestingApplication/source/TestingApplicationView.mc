// =============================================================
// TestingApplicationView.mc
//
// Minimal status display. NO high-rate IMU listener — the screen
// is free to sleep. The SensorLogger records accel/gyro to the FIT
// file at full rate independently of this view.
//
// The display shows: recording status, HR, and FIT files saved.
// It updates only on HR events (~1Hz) and when a FIT file is saved.
// =============================================================

import Toybox.WatchUi;
import Toybox.Sensor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Application.Storage;

class TestingApplicationView extends WatchUi.View {

    var _heartRate   = null;
    var _temperature = null;
    var _backHint    = 0;
    var _listenerActive = false;
    var _screenVisible  = false;

    function initialize() {
        View.initialize();
        System.println("=== TestingApplication VIEW STARTED ===");
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _registerListeners();
    }

    function onShow() as Void {
        _screenVisible = true;
        _registerListeners();
        System.println("[VIEW] onShow — screen on");
    }

    function onHide() as Void {
        _screenVisible = false;
        // Keep the HR listener running for data, but stop redrawing.
        System.println("[VIEW] onHide — screen off, FIT still recording");
    }

    function _registerListeners() as Void {
        if (_listenerActive) { return; }
        _listenerActive = true;

        // Only low-cost HR + Temp (event-driven, ~1Hz). NO high-rate IMU
        // listener — that would pin the CPU and keep the screen on.
        Sensor.setEnabledSensors([
            Sensor.SENSOR_HEARTRATE,
            Sensor.SENSOR_TEMPERATURE
        ]);
        Sensor.enableSensorEvents(method(:onSensor));
        System.println("[VIEW] HR/Temp listener active (screen free to sleep)");
    }

    // HR + Temp event (~1 Hz)
    function onSensor(info as Sensor.Info) as Void {
        if (info has :heartRate && info.heartRate != null) {
            _heartRate = info.heartRate;
        }
        if (info has :temperature && info.temperature != null) {
            _temperature = info.temperature;
        }
        // Only redraw if the screen is actually visible. Calling
        // requestUpdate() while the screen is dimmed wakes it back up
        // and wastes battery. When hidden, we just store the value.
        if (_screenVisible) {
            WatchUi.requestUpdate();
        }
    }

    function nextPage() as Void {
        if (_screenVisible) {
            WatchUi.requestUpdate();
        }
    }

    function confirmExit() as Void {
        getApp().saveAndExit();
    }

    function showBackHint(count) as Void {
        _backHint = count;
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    // Draw — single status page
    // ----------------------------------------------------------
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        // Title
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 25, Graphics.FONT_SMALL, "SENSOR LOG", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(30, 60, w - 30, 60);

        // Recording status
        var status = Storage.getValue("session_status");
        var statusColor = Graphics.COLOR_RED;
        var statusText  = "not recording";
        if (status != null && status.equals("recording")) {
            statusColor = Graphics.COLOR_GREEN;
            statusText  = "RECORDING";
        } else if (status != null && status.equals("saved")) {
            statusColor = Graphics.COLOR_BLUE;
            statusText  = "SAVED";
        }
        dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 85, Graphics.FONT_MEDIUM, statusText, Graphics.TEXT_JUSTIFY_CENTER);

        // FIT files saved (the main counter, updates every 5 min)
        var files = Storage.getValue("files_saved");
        if (files == null) { files = 0; }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 150, Graphics.FONT_XTINY, "FIT FILES SAVED", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 175, Graphics.FONT_NUMBER_MEDIUM, files.toString(), Graphics.TEXT_JUSTIFY_CENTER);

        // Heart rate
        var hrStr = (_heartRate != null) ? _heartRate.toString() + " bpm" : "-- bpm";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 250, Graphics.FONT_SMALL, hrStr, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 290, Graphics.FONT_XTINY, "auto-saves every 5 min", Graphics.TEXT_JUSTIFY_CENTER);

        // Connection heartbeat status
        var connOk = Storage.getValue("connection_ok");
        var pings  = Storage.getValue("ping_count");
        if (pings == null) { pings = 0; }
        if (connOk != null && connOk == true) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w/2, 315, Graphics.FONT_XTINY,
                "connection OK (" + pings + ")", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w/2, 315, Graphics.FONT_XTINY,
                "no connection (" + pings + ")", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Back-button exit hint
        if (_backHint > 0) {
            var remaining = 3 - _backHint;
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w/2, h - 60, Graphics.FONT_XTINY,
                "press back " + remaining + "x to stop", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w/2, h - 60, Graphics.FONT_XTINY,
                "back 3x = stop & save", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

}
