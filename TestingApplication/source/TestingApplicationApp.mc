// =============================================================
// TestingApplicationApp.mc
// Cycle: 10 min record → 2 min sync gap → 10 min record → repeat
//
// Uses Time.now() to track actual elapsed time instead of relying
// purely on timers — timers can drift or miss when watch sleeps.
// A short polling timer checks every 30 seconds if it is time
// to rotate or restart, so sleep never causes a missed transition.
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

    var _logger          = null;
    var _session         = null;
    var _pollTimer       = null;  // 30-sec polling timer — drives all transitions
    var _restartAttempts = 0;
    var _fileCount       = 0;
    var _heartbeatCount  = 0;

    // Timestamps (unix seconds) tracking current phase
    var _recordStartTs   = null;  // when current recording started
    var _syncStartTs     = null;  // when current sync gap started
    var _phase           = "idle"; // "recording" | "syncing"

    const RECORD_SECS   = 10 * 60;  // 10 minutes
    const SYNC_SECS     =  2 * 60;  // 2 minutes
    const POLL_MS       = 30 * 1000; // poll every 30 seconds

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

        // Single polling timer drives all transitions — survives sleep
        _pollTimer = new Timer.Timer();
        _pollTimer.start(method(:onPoll), POLL_MS, true); // repeating every 30 sec
        System.println("[TIMER] Poll timer started (30s interval)");
    }

    // Called every 30 seconds — checks if it is time to rotate or restart
    function onPoll() as Void {
        var now = Time.now().value();

        if (_phase.equals("recording")) {
            var elapsed = now - _recordStartTs;
            System.println("[POLL] Recording " + elapsed + "s / " + RECORD_SECS + "s");

            if (elapsed >= RECORD_SECS) {
                System.println("[POLL] Record time reached — rotating");
                _rotateSession();
            }

        } else if (_phase.equals("syncing")) {
            var elapsed = now - _syncStartTs;
            System.println("[POLL] Syncing " + elapsed + "s / " + SYNC_SECS + "s");

            if (elapsed >= SYNC_SECS) {
                System.println("[POLL] Sync gap done — starting new session");
                _startNextSession();
            }
        }
    }

    // Step 1: Save current session, enter sync gap
    function _rotateSession() as Void {
        _phase = "idle";
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

        // Null logger — exits activity mode so Garmin Connect can sync
        _logger = null;
        _phase  = "syncing";
        _syncStartTs = Time.now().value();
        Storage.setValue("session_status", "syncing");
        System.println("[SESSION] Sync gap started at " + _syncStartTs);
        _sendHeartbeat();
    }

    // Step 2: Start the next recording session
    function _startNextSession() as Void {
        _phase = "idle";
        _startSensorLogger();
        _startFitSession();

        if (_session != null && _session.isRecording()) {
            _restartAttempts = 0;
            System.println("[SESSION] New session recording OK");
        } else if (_restartAttempts < 5) {
            // Not ready yet — next poll will retry in 30 sec
            _restartAttempts++;
            _phase = "syncing"; // stay in syncing phase so poll retries
            System.println("[SESSION] Not recording yet, retry " + _restartAttempts + " on next poll");
        } else {
            _restartAttempts = 0;
            System.println("[SESSION] ERROR: could not start after 5 retries");
        }
    }

    function onStop(state as Dictionary?) as Void {
        _phase = "idle";
        if (_pollTimer != null) { _pollTimer.stop(); _pollTimer = null; }

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
        if (!(Toybox has :ActivityRecording)) {
            System.println("[SESSION] ActivityRecording not available");
            return;
        }
        if (_session != null && _session.isRecording()) {
            System.println("[SESSION] Already recording");
            return;
        }

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

            _phase         = "recording";
            _recordStartTs = Time.now().value();
            Storage.setValue("session_status", "recording");
            System.println("[SESSION] Started: " + name);
        } catch (ex) {
            _session = null;
            System.println("[SESSION] createSession failed — will retry on next poll");
            Storage.setValue("session_status", "retrying");
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
        System.println("[PING] Sending heartbeat #" + _heartbeatCount);
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
            System.println("[PING] OK — connection alive");
        } else if (responseCode == -104) {
            Storage.setValue("connection_ok", false);
            System.println("[PING] -104 — no BLE");
        } else {
            Storage.setValue("connection_ok", false);
            System.println("[PING] Failed: " + responseCode);
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view     = new TestingApplicationView();
        var delegate = new TestingApplicationDelegate(view);
        return [ view, delegate ];
    }

}

function getApp() as TestingApplicationApp {
    return Application.getApp() as TestingApplicationApp;
}
