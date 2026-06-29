// =============================================================
// TestingApplicationApp.mc
// Cycle: 1 hour record → 3 sec save gap → 1 hour record → repeat
// =============================================================

import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.ActivityRecording;
import Toybox.Activity;
import Toybox.SensorLogging;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.Communications;

class TestingApplicationApp extends Application.AppBase {

    var _logger         = null;
    var _session        = null;
    var _pollTimer      = null;  // repeating 30-sec poll — sleep-safe
    var _restartTimer   = null;  // one-shot 3-sec save gap
    var _fileCount      = 0;
    var _heartbeatCount = 0;
    var _recordStartTs  = null;  // unix timestamp when recording started

    const RECORD_SECS = 60 * 60;  // 1 hour
    const POLL_MS     = 30 * 1000; // check every 30 sec
    const SAVE_GAP_MS = 3 * 1000;  // 3 sec gap for save() to complete

    const HEARTBEAT_URL = "https://httpbin.org/get";

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        System.println("[APP] Started");
        _startSensorLogger();
        _startFitSession();
        _sendHeartbeat();
        Storage.setValue("app_start_ts", Time.now().value());

        // Repeating 30-sec poll checks real elapsed time — survives sleep
        _pollTimer = new Timer.Timer();
        _pollTimer.start(method(:onPoll), POLL_MS, true);
        System.println("[TIMER] Poll timer started (30s)");
    }

    // Fires every 30 sec — checks if 1 hour has elapsed
    function onPoll() as Void {
        if (_recordStartTs == null || _session == null) { return; }

        var elapsed = Time.now().value() - _recordStartTs;
        System.println("[POLL] Recording " + elapsed + "s / " + RECORD_SECS + "s");

        if (elapsed >= RECORD_SECS) {
            System.println("[POLL] 1 hour reached — rotating session");
            _sendHeartbeat();
            _rotateSession();
        }
    }

    // Stop + save current session, wait 3 sec, start new one
    function _rotateSession() as Void {
        _saveLoggerStats();

        if (_session != null) {
            try {
                if (_session.isRecording()) { _session.stop(); }
                _session.save();
                _fileCount++;
                Storage.setValue("files_saved", _fileCount);
                System.println("[SESSION] Saved FIT file #" + _fileCount);
            } catch (ex instanceof Lang.Exception) {
                System.println("[SESSION] Save error: " + ex.getErrorMessage());
            }
            _session = null;
        }
        _logger = null;

        // 3-sec gap lets save() fully release the slot before createSession
        _restartTimer = new Timer.Timer();
        _restartTimer.start(method(:onRestartSession), SAVE_GAP_MS, false);
        System.println("[SESSION] Waiting 3s for save to complete...");
    }

    // Called 3 sec after save — start the next session immediately
    function onRestartSession() as Void {
        _restartTimer = null;
        System.println("[SESSION] Starting next session");
        _startSensorLogger();
        _startFitSession();
    }

    function onStop(state as Dictionary?) as Void {
        if (_pollTimer    != null) { _pollTimer.stop();    _pollTimer    = null; }
        if (_restartTimer != null) { _restartTimer.stop(); _restartTimer = null; }

        _saveLoggerStats();
        if (_session != null) {
            try {
                if (_session.isRecording()) { _session.stop(); }
                _session.save();
                Storage.setValue("session_status", "saved");
                System.println("[SESSION] Final save on exit");
            } catch (ex instanceof Lang.Exception) {
                System.println("[SESSION] Final save error: " + ex.getErrorMessage());
            }
        }
        _session = null;
        _logger  = null;
        System.println("[APP] Stopped");
    }

    function saveAndExit() as Void {
        onStop(null);
        System.exit();
    }

    function _startFitSession() as Void {
        if (!(Toybox has :ActivityRecording)) { return; }
        if (_session != null && _session.isRecording()) { return; }

        try {
            var now  = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            var name = "SensorLog_"
                + now.year.format("%04d") + "-"
                + now.month.format("%02d") + "-"
                + now.day.format("%02d") + "_"
                + now.hour.format("%02d") + "-"
                + now.min.format("%02d");

            _session = ActivityRecording.createSession({
                :name         => name,
                :sport        => Activity.SPORT_GENERIC,
                :subSport     => Activity.SUB_SPORT_GENERIC,
                :sensorLogger => _logger
            });

            if (!_session.isRecording()) { _session.start(); }

            _recordStartTs = Time.now().value();
            Storage.setValue("session_status", "recording");
            System.println("[SESSION] Started: " + name);
        } catch (ex) {
            _session = null;
            System.println("[SESSION] createSession failed: " + ex);
            Storage.setValue("session_status", "failed");
        }
    }

    function _startSensorLogger() as Void {
        if (_logger != null) { return; }
        try {
            _logger = new SensorLogging.SensorLogger({
                :accelerometer => { :enabled => true },
                :gyroscope     => { :enabled => true }
            });
            Storage.setValue("logger_status", "running");
            System.println("[LOGGER] Started");
        } catch (ex instanceof Lang.Exception) {
            _logger = null;
            Storage.setValue("logger_status", "failed");
            System.println("[LOGGER] Failed: " + ex.getErrorMessage());
        }
    }

    function _saveLoggerStats() as Void {
        if (_logger == null) { return; }
        try {
            var stats = _logger.getStats2(null);
            if (stats != null) {
                if (stats has :accelerometer && stats[:accelerometer] != null) {
                    Storage.setValue("accel_samples", stats[:accelerometer].sampleCount);
                    System.println("[STATS] Accel: " + stats[:accelerometer].sampleCount);
                }
                if (stats has :gyroscope && stats[:gyroscope] != null) {
                    Storage.setValue("gyro_samples", stats[:gyroscope].sampleCount);
                    System.println("[STATS] Gyro: " + stats[:gyroscope].sampleCount);
                }
            }
        } catch (ex instanceof Lang.Exception) {
            System.println("[STATS] Error: " + ex.getErrorMessage());
        }
    }

    function _sendHeartbeat() as Void {
        if (!(Communications has :makeWebRequest)) { return; }
        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        var params = { "device" => "vivoactive6", "ping" => _heartbeatCount };
        System.println("[PING] Heartbeat #" + _heartbeatCount);
        Communications.makeWebRequest(HEARTBEAT_URL, params, options,
            method(:onHeartbeatResponse));
    }

    function onHeartbeatResponse(
        responseCode as Number,
        data as Dictionary or String or Null
    ) as Void {
        _heartbeatCount++;
        Storage.setValue("ping_count", _heartbeatCount);
        Storage.setValue("last_ping_code", responseCode);
        if (responseCode == 200) {
            Storage.setValue("connection_ok", true);
            System.println("[PING] OK");
        } else if (responseCode == -104) {
            Storage.setValue("connection_ok", false);
            System.println("[PING] -104 no BLE");
        } else {
            Storage.setValue("connection_ok", false);
            System.println("[PING] Failed: " + responseCode);
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new TestingApplicationView();
        return [ view, new TestingApplicationDelegate(view) ];
    }

}

function getApp() as TestingApplicationApp {
    return Application.getApp() as TestingApplicationApp;
}
