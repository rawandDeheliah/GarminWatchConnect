// =============================================================
// MyAppView.mc
// Display: date, time, heart rate with red/pink/gray theme
// =============================================================

import Toybox.WatchUi;
import Toybox.Sensor;
import Toybox.Activity;
import Toybox.Timer;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Application.Storage;

class TestingApplicationView extends WatchUi.View {

    var _heartRate      = null;
    var _backHint       = 0;
    var _listenerActive = false;
    var _screenVisible  = false;
    var _hrTimer        = null;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _registerListeners();
    }

    function onShow() as Void {
        _screenVisible = true;
        _registerListeners();
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        _screenVisible = false;
        if (_hrTimer != null) {
            _hrTimer.stop();
            _hrTimer = null;
            _listenerActive = false;
        }
    }

    function _registerListeners() as Void {
        if (_listenerActive) { return; }
        _listenerActive = true;
        // Poll every 2 sec using both sources — Sensor.enableSensorEvents
        // conflicts with the active ActivityRecording session on real hardware
        _hrTimer = new Timer.Timer();
        _hrTimer.start(method(:onHrPoll), 120000, true);
        System.println("[HR] Poll timer started");
    }

    function onHrPoll() as Void {
        var gotHr = false;

        // Source 1: Activity.getActivityInfo() — works during active session
        try {
            var actInfo = Activity.getActivityInfo();
            if (actInfo != null && actInfo.currentHeartRate != null) {
                _heartRate = actInfo.currentHeartRate;
                gotHr = true;
                System.println("[HR] Activity: " + _heartRate);
            }
        } catch (ex instanceof Lang.Exception) {}

        // Source 2: Sensor.getInfo() — works without active session
        if (!gotHr) {
            try {
                var sInfo = Sensor.getInfo();
                if (sInfo != null && sInfo.heartRate != null) {
                    _heartRate = sInfo.heartRate;
                    System.println("[HR] Sensor: " + _heartRate);
                } else {
                    System.println("[HR] both sources null");
                }
            } catch (ex instanceof Lang.Exception) {}
        }

        if (_screenVisible) { WatchUi.requestUpdate(); }
    }

    function nextPage() as Void {
        if (_screenVisible) { WatchUi.requestUpdate(); }
    }

    function confirmExit() as Void {
        getApp().saveAndExit();
    }

    function showBackHint(count) as Void {
        _backHint = count;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // ── Background ──────────────────────────────────────────
        dc.setColor(0x1A1A1A, 0x1A1A1A);  // very dark gray
        dc.clear();

        // ── Get current time ────────────────────────────────────
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        // ── Heart emoji + HR ────────────────────────────────────
        // Red heart circle background
        var cx = w / 2;
        dc.setColor(0xFF2D55, Graphics.COLOR_TRANSPARENT);  // vivid red-pink
        dc.fillCircle(cx, 58, 36);

        // Heart symbol
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        // Draw heart using filled circles and polygon
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 10, 54, 10.06);
        dc.fillCircle(cx + 10, 54, 10.06);
        var heartPoints = [
            [cx - 20, 55.3],
            [cx + 20, 55.3],
            [cx, 78]
        ];
        dc.fillPolygon(heartPoints);

        // Cover white corner gaps — match the red circle color
dc.setColor(0xFF2D55, Graphics.COLOR_TRANSPARENT);

// Left corner: after left edge of trangle
dc.fillPolygon([
    [cx + 21, 54],
    [cx + 30,  54],
    [cx + 30,  78],
    [cx+1 , 78]
]);

// Left corner: after left edge of trangle
dc.fillPolygon([
    [cx - 21, 54],
    [cx - 30,  54],
    [cx - 30,  78],
    [cx-1 , 78]
]);

        // HR value
        var hrStr = (_heartRate != null) ? _heartRate.toString() : "--";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
       dc.drawText(cx, 90, Graphics.FONT_NUMBER_MILD, hrStr,
        Graphics.TEXT_JUSTIFY_CENTER);

        // "BPM" label
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);  // mid gray
        dc.drawText(cx, 165, Graphics.FONT_XTINY, "BPM", Graphics.TEXT_JUSTIFY_CENTER);

        // ── Divider ─────────────────────────────────────────────
        dc.setColor(0xFF2D55, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - 60, 195, 120, 2);

        // ── Date ────────────────────────────────────────────────
        // Year - Month - Day
        var dateStr = now.year.format("%04d") + " - "
            + now.month.format("%02d") + " - "
            + now.day.format("%02d");

        dc.setColor(0xFFB3C1, Graphics.COLOR_TRANSPARENT);  // soft pink
        dc.drawText(cx, 200, Graphics.FONT_SMALL, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER);

        // ── Time ────────────────────────────────────────────────
        // Hour : Min  (large)
        var timeStr = now.hour.format("%02d") + ":" + now.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 230, Graphics.FONT_NUMBER_MEDIUM, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER);

        // ── Recording status dot ────────────────────────────────
        var status = Storage.getValue("session_status");
        var dotColor = 0x555555;  // gray = not recording
        if (status != null && status.equals("recording")) {
            dotColor = 0xFF2D55;  // red = recording
        } else if (status != null && status.equals("saved")) {
            dotColor = 0x30D158;  // green = saved
        }
        dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, h - 55, 6);

        // Status label
        var statusLabel = "not recording";
        if (status != null && status.equals("recording")) { statusLabel = "recording"; }
        else if (status != null && status.equals("saved")) { statusLabel = "saved"; }
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - 45, Graphics.FONT_XTINY, statusLabel,
            Graphics.TEXT_JUSTIFY_CENTER);

        // ── Back hint ───────────────────────────────────────────
        if (_backHint > 0) {
            var remaining = 3 - _backHint;
            dc.setColor(0xFFD60A, Graphics.COLOR_TRANSPARENT);  // yellow
            dc.drawText(cx, h - 25, Graphics.FONT_XTINY,
                "back " + remaining + "x to stop", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

}
