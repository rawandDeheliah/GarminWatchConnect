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

    // Save current FIT file, then start a fresh session after a short
    // delay. The delay is critical: save() of a large (~860KB) file does
    // not release the recording slot instantly. If we call createSession
    // too soon, it throws "Cannot create a new session while recording is
    // active", the new session fails to start, and we get a ~5-min GAP
    // until the next timer tick. The delay lets save() fully complete.
    function _rotateSession() as Void {
        _saveLoggerStats();

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

        // Wait 3 seconds for save() to fully release the session slot,
        // THEN start the next session. This closes the gap.
        var restartTimer = new Timer.Timer();
        restartTimer.start(method(:onRestartSession), 3000, false);
    }

    // Called 3 seconds after save() — starts the next recording session.
    // If the session slot is still busy (save not fully done), retry a few
    // times rather than giving up (which would cause a 5-min gap).
    var _restartAttempts = 0;
    function onRestartSession() as Void {
        _startSensorLogger();

        // Try to start the session; verify it actually began recording
        _startFitSession();

        if (_session != null && _session.isRecording()) {
            _restartAttempts = 0;
            System.println("[SESSION] Next session started after save");
        } else if (_restartAttempts < 5) {
            // Slot still busy — wait another 2s and retry
            _restartAttempts++;
            System.println("[SESSION] Slot busy, retry " + _restartAttempts);
            var retry = new Timer.Timer();
            retry.start(method(:onRestartSession), 2000, false);
        } else {
            _restartAttempts = 0;
            System.println("[SESSION] Could not restart after retries");
        }
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
            // Slot still busy (previous save() not fully released) or a
            // leftover session exists. Null our reference so the retry
            // logic in onRestartSession knows the start did NOT succeed.
            _session = null;
            System.println("[SESSION] createSession failed — slot busy, will retry");
            Storage.setValue("session_status", "retrying");
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
