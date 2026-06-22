// =============================================================
// TestingApplicationApp.mc
//
// Simple, reliable session model:
//   onStart  → create + start session + logger
//   onStop   → stop + save session  (writes the FIT file)
//
// No Storage flags, no background re-creation, no lost references.
// The session lives exactly as long as the app instance.
// Recording continues while app is backgrounded (Garmin keeps the
// activity engine alive); the FIT file is written when the app
// fully exits and onStop fires.
// =============================================================

import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.ActivityRecording;
import Toybox.Activity;
import Toybox.Background;
import Toybox.SensorLogging;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;

class TestingApplicationApp extends Application.AppBase {

    var _logger  = null;
    var _session = null;
    var _saveTimer = null;
    var _fileCount = 0;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        _startSensorLogger();
        _startFitSession();

        // Auto-save timer — saves current FIT and starts a new session
        // every 5 minutes so data is never lost. This runs in the
        // foreground app context which owns the session.
        // NOTE: We do NOT use a background temporal event — that runs in
        // a separate context that would conflict with our session and
        // cause "Cannot create a new session" errors.
        _saveTimer = new Timer.Timer();
        _saveTimer.start(method(:onSaveTimer), 5 * 60 * 1000, true); // 5 min, repeating

        Storage.setValue("app_start_ts", Time.now().value());
        System.println("[APP] Started with 5-min auto-save");
    }

    // Fires every 5 minutes — saves current session, starts a new one
    function onSaveTimer() as Void {
        System.println("[TIMER] 5-min auto-save triggered");
        _rotateSession();
    }

    // Save current FIT file and immediately start a fresh session
    function _rotateSession() as Void {
        _saveLoggerStats();

        // Save current session (writes the FIT file)
        if (_session != null) {
            try {
                if (_session.isRecording()) {
                    _session.stop();
                }
                _session.save();
                _fileCount++;
                Storage.setValue("files_saved", _fileCount);
                System.println("[SESSION] Auto-saved FIT file #" + _fileCount);
            } catch (ex instanceof Lang.Exception) {
                System.println("[SESSION] Auto-save error: " + ex.getErrorMessage());
            }
            _session = null;
        }

        // Restart logger + session for the next 5-min chunk
        _startSensorLogger();
        _startFitSession();
    }

    function onStop(state as Dictionary?) as Void {
        // Stop the auto-save timer
        if (_saveTimer != null) {
            _saveTimer.stop();
            _saveTimer = null;
        }

        _saveLoggerStats();
        // Final save of the current session
        if (_session != null) {
            try {
                if (_session.isRecording()) {
                    _session.stop();
                }
                _session.save();
                Storage.setValue("session_status", "saved");
                System.println("[SESSION] Final save on stop");
            } catch (ex instanceof Lang.Exception) {
                System.println("[SESSION] Save error: " + ex.getErrorMessage());
            }
        }
        _session = null;
        _logger  = null;
        System.println("[APP] Stopped");
    }

    // Called when user confirms exit (back 3x) — save then close app
    function saveAndExit() as Void {
        onStop(null);
        System.exit();
    }

    function _startFitSession() as Void {
        if (!(Toybox has :ActivityRecording)) {
            System.println("[SESSION] ActivityRecording not supported");
            return;
        }

        // If we already hold a recording session, do nothing
        if (_session != null && _session.isRecording()) {
            System.println("[SESSION] Already holding active session");
            Storage.setValue("session_status", "recording");
            return;
        }

        try {
            _session = ActivityRecording.createSession({
                :name         => "SensorLog",
                :sport        => Activity.SPORT_GENERIC,
                :subSport     => Activity.SUB_SPORT_GENERIC,
                :sensorLogger => _logger
            });
            if (!_session.isRecording()) {
                _session.start();
                System.println("[SESSION] FIT session started");
            } else {
                System.println("[SESSION] Recovered active session");
            }
            Storage.setValue("session_status", "recording");
        } catch (ex) {
            // Bare catch — System Errors are NOT Lang.Exception subclasses
            // A session is already recording at the OS level (e.g. leftover
            // simulator state). We can't get a reference, so just mark status.
            System.println("[SESSION] Session already active at OS level");
            Storage.setValue("session_status", "recording");
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view     = new TestingApplicationView();
        var delegate = new TestingApplicationDelegate(view);
        return [ view, delegate ];
    }

    function _startSensorLogger() as Void {
        try {
            _logger = new SensorLogging.SensorLogger({
                :accelerometer => { :enabled => true },
                :gyroscope     => { :enabled => true }
            });
            Storage.setValue("logger_status", "running");
            System.println("[LOGGER] Started");
        } catch (ex instanceof Lang.Exception) {
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

}

function getApp() as TestingApplicationApp {
    return Application.getApp() as TestingApplicationApp;
}
