// =============================================================
// TestingApplicationView.mc
// Device: vivoactive6
//
// Displays live sensor data
// FIT session + SensorLogger run automatically from app code
// registerSensorDataListener shows live values on screen
// =============================================================

import Toybox.WatchUi;
import Toybox.Sensor;
import Toybox.Graphics;
import Toybox.Position;
import Toybox.Lang;
import Toybox.System;
import Toybox.Application.Storage;
import Toybox.Time;
import Toybox.Attention;

class TestingApplicationView extends WatchUi.View {

    // Live sensor values for display
    var _heartRate   = null;
    var _temperature = null;
    var _pressure    = null;
    var _altitude    = null;
    var _gpsLat      = null;
    var _gpsLon      = null;
    var _speed       = null;
    var _accelX      = null;
    var _accelY      = null;
    var _accelZ      = null;
    var _gyroX       = null;
    var _gyroY       = null;
    var _gyroZ       = null;

    // Storage sample counter
    var _sampleCount = 0;
    var _backHint    = 0;

    // Pages: 0=Status | 1=HR+Temp | 2=Accel | 3=Gyro | 4=GPS
    var _page = 0;

    function initialize() {
        View.initialize();
        var saved = Storage.getValue("sample_count");
        var previous = (saved != null) ? saved : 0;
        System.println("=== TestingApplication VIEW STARTED ===");
        System.println("[VIEW] Previous session samples: " + previous
            + " (~" + (previous / 3600) + " hours of data in Storage)");
        // Reset counter for this new session
        _sampleCount = 0;
        Storage.setValue("sample_count", 0);
    }

    var _listenerActive = false;

    function onLayout(dc as Graphics.Dc) as Void {
        _registerDisplayListener();
    }

    // Called every time the view becomes visible (screen wakes)
    function onShow() as Void {
        _registerDisplayListener();
        System.println("[VIEW] onShow");
    }

    // Called when view is hidden (screen off / app backgrounded)
    // The FIT session + SensorLogger KEEP RECORDING at firmware level.
    function onHide() as Void {
        // Unregister display listener so it can be cleanly re-registered
        Sensor.unregisterSensorDataListener();
        _listenerActive = false;
        System.println("[VIEW] onHide — screen off, FIT still recording");
    }

    function _registerDisplayListener() as Void {
        // Avoid double-registration which throws
        // "More than one instance of data listener not allowed"
        if (_listenerActive) {
            return;
        }

        var imuOptions = {
            :period        => 1,
            :accelerometer => { :enabled => true, :sampleRate => 100 },
            :gyroscope     => { :enabled => true, :sampleRate => 100 }
        };
        Sensor.registerSensorDataListener(method(:onSensorData), imuOptions);
        _listenerActive = true;

        Sensor.setEnabledSensors([
            Sensor.SENSOR_HEARTRATE,
            Sensor.SENSOR_TEMPERATURE
        ]);
        Sensor.enableSensorEvents(method(:onSensor));

        Position.enableLocationEvents(
            Position.LOCATION_CONTINUOUS,
            method(:onPosition)
        );
        System.println("[VIEW] Display listeners registered @ 100Hz");
    }

    // ----------------------------------------------------------
    // Standard 1Hz callback
    // ----------------------------------------------------------
    function onSensor(info as Sensor.Info) as Void {
        if (info has :heartRate && info.heartRate != null) {
            _heartRate = info.heartRate;
            System.println("[HR] " + _heartRate + " bpm");
        }
        if (info has :temperature && info.temperature != null) {
            // Only log temp when it changes
            var newTemp = info.temperature;
            if (_temperature == null || newTemp != _temperature) {
                _temperature = newTemp;
                System.println("[TEMP] " + _temperature + " C");
            }
        }
        if (info has :pressure && info.pressure != null) {
            _pressure = info.pressure;
        }
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    // IMU callback @ 100Hz — display latest sample
    // SensorLogger is recording ALL 100 samples to FIT in parallel
    // ----------------------------------------------------------
    function onSensorData(sensorData as Sensor.SensorData) as Void {

        if (sensorData has :accelerometerData && sensorData.accelerometerData != null) {
            var a = sensorData.accelerometerData;
            if (a.x != null && a.x.size() > 0) {
                var i = a.x.size() - 1;
                _accelX = a.x[i];
                _accelY = a.y[i];
                _accelZ = a.z[i];
                // Keep latest in Storage so background can read it
                Storage.setValue("current_accel_x", _accelX);
                Storage.setValue("current_accel_y", _accelY);
                Storage.setValue("current_accel_z", _accelZ);
            }
        }

        if (sensorData has :gyroscopeData && sensorData.gyroscopeData != null) {
            var g = sensorData.gyroscopeData;
            if (g.x != null && g.x.size() > 0) {
                var i = g.x.size() - 1;
                _gyroX = g.x[i];
                _gyroY = g.y[i];
                _gyroZ = g.z[i];
                // Keep latest in Storage so background can read it
                Storage.setValue("current_gyro_x", _gyroX);
                Storage.setValue("current_gyro_y", _gyroY);
                Storage.setValue("current_gyro_z", _gyroZ);
            }
        }

        // Save snapshot to Storage every 60 samples (~60 seconds)
        _sampleCount++;
        if (_sampleCount % 60 == 0) {
            _saveSnapshot();
        }
        Storage.setValue("sample_count", _sampleCount);

        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    // Save snapshot to Storage every 60 seconds
    // ----------------------------------------------------------
    function _saveSnapshot() as Void {
        var ts  = Time.now().value();
        var idx = (_sampleCount / 60) % 1440; // 24h of 1-min snapshots

        Storage.setValue("snap_" + idx + "_ts",   ts);
        Storage.setValue("snap_" + idx + "_ax",   _accelX);
        Storage.setValue("snap_" + idx + "_ay",   _accelY);
        Storage.setValue("snap_" + idx + "_az",   _accelZ);
        Storage.setValue("snap_" + idx + "_gx",   _gyroX);
        Storage.setValue("snap_" + idx + "_gy",   _gyroY);
        Storage.setValue("snap_" + idx + "_gz",   _gyroZ);
        Storage.setValue("snap_" + idx + "_hr",   _heartRate);
        Storage.setValue("snap_" + idx + "_temp", _temperature);

        System.println("[SNAP] #" + (_sampleCount / 60)
            + " | ax=" + _fmt(_accelX) + " ay=" + _fmt(_accelY) + " az=" + _fmt(_accelZ)
            + " | gx=" + _fmt(_gyroX)  + " gy=" + _fmt(_gyroY)  + " gz=" + _fmt(_gyroZ)
            + " | hr=" + _heartRate + " | ts=" + ts);
    }

    // GPS callback
    function onPosition(info as Position.Info) as Void {
        if (info.position != null) {
            var coords = info.position.toDegrees();
            _gpsLat = coords[0];
            _gpsLon = coords[1];
        }
        if (info has :altitude && info.altitude != null) { _altitude = info.altitude; }
        if (info has :speed    && info.speed    != null) { _speed    = info.speed;    }
        WatchUi.requestUpdate();
    }

    function nextPage() as Void {
        _page = (_page + 1) % 5;
        WatchUi.requestUpdate();
    }

    // Called by delegate when user holds back 3x — save and exit
    function confirmExit() as Void {
        var app = getApp();
        app.saveAndExit();
    }

    // Show "press back Nx to stop" hint on screen
    function showBackHint(count) as Void {
        _backHint = count;
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    // Draw
    // ----------------------------------------------------------
    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if      (_page == 0) { _drawStatus(dc, w, h); }
        else if (_page == 1) { _drawHRTemp(dc, w, h); }
        else if (_page == 2) { _drawAccel(dc, w, h);  }
        else if (_page == 3) { _drawGyro(dc, w, h);   }
        else                 { _drawGpsAlt(dc, w, h); }

        _drawDots(dc, w, h);
    }

    // Page 0: Session Status
    function _drawStatus(dc as Graphics.Dc, w as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 20, Graphics.FONT_SMALL, "", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 55, w - 20, 55);

        // FIT session status
        var sessionStatus = Storage.getValue("session_status");
        var sessionColor  = Graphics.COLOR_RED;
        var sessionLabel  = sessionStatus != null ? sessionStatus : "--";
        if (sessionStatus != null) {
            if (sessionStatus.equals("recording"))        { sessionColor = Graphics.COLOR_GREEN;  }
            else if (sessionStatus.equals("saved"))       { sessionColor = Graphics.COLOR_BLUE;   }
            else if (sessionStatus.equals("cleared"))     { sessionColor = Graphics.COLOR_ORANGE; }
            else if (sessionStatus.equals("already_recording")) { sessionColor = Graphics.COLOR_YELLOW; }
        }
        dc.setColor(sessionColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 70, Graphics.FONT_XTINY, "FIT SESSION", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w/2, 95, Graphics.FONT_SMALL, sessionLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // Logger status
        var loggerStatus = Storage.getValue("logger_status");
        var loggerColor  = (loggerStatus != null && loggerStatus.equals("running"))
            ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW;
        dc.setColor(loggerColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 155, Graphics.FONT_XTINY, "SENSOR LOGGER", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w/2, 180, Graphics.FONT_SMALL,
            loggerStatus != null ? loggerStatus : "--",
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 230, w - 20, 230);

        // Sample counts
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 245, Graphics.FONT_XTINY, "DISPLAY SAMPLES", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 265, Graphics.FONT_MEDIUM, _sampleCount.toString(), Graphics.TEXT_JUSTIFY_CENTER);

        // FIT files saved so far (auto-saved every 5 min)
        var filesSaved = Storage.getValue("files_saved");
        if (filesSaved == null) { filesSaved = 0; }
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 330, Graphics.FONT_XTINY,
            "FIT files saved: " + filesSaved, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 360, Graphics.FONT_XTINY,
            "auto-saves every 5 min", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Page 1: Heart Rate + Temperature
    function _drawHRTemp(dc as Graphics.Dc, w as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 30, Graphics.FONT_SMALL, "HEART RATE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 65, w - 20, 65);

        var hrStr = (_heartRate != null) ? _heartRate.toString() : "--";
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 80, Graphics.FONT_NUMBER_MEDIUM, hrStr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 165, Graphics.FONT_XTINY, "bpm", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 200, w - 20, 200);

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 215, Graphics.FONT_SMALL, "TEMPERATURE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 255, Graphics.FONT_NUMBER_MEDIUM, _fmt(_temperature), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 340, Graphics.FONT_XTINY, "celsius", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Page 2: Accelerometer
    function _drawAccel(dc as Graphics.Dc, w as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 20, Graphics.FONT_SMALL, "ACCELEROMETER", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 50, Graphics.FONT_XTINY, "milli-G  @ 100Hz -> FIT", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 75, w - 20, 75);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 100, Graphics.FONT_MEDIUM, "X", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w-40, 100, Graphics.FONT_MEDIUM, _fmt(_accelX), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 190, Graphics.FONT_MEDIUM, "Y", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w-40, 190, Graphics.FONT_MEDIUM, _fmt(_accelY), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 280, Graphics.FONT_MEDIUM, "Z", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w-40, 280, Graphics.FONT_MEDIUM, _fmt(_accelZ), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 370, Graphics.FONT_XTINY,
            "Logger -> FIT: " + Storage.getValue("logger_status"),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Page 3: Gyroscope
    function _drawGyro(dc as Graphics.Dc, w as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 20, Graphics.FONT_SMALL, "GYROSCOPE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 50, Graphics.FONT_XTINY, "deg/sec  @ 100Hz -> FIT", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 75, w - 20, 75);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 100, Graphics.FONT_MEDIUM, "X", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w-40, 100, Graphics.FONT_MEDIUM, _fmt(_gyroX), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 190, Graphics.FONT_MEDIUM, "Y", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w-40, 190, Graphics.FONT_MEDIUM, _fmt(_gyroY), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 280, Graphics.FONT_MEDIUM, "Z", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w-40, 280, Graphics.FONT_MEDIUM, _fmt(_gyroZ), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 370, Graphics.FONT_XTINY,
            "Logger -> FIT: " + Storage.getValue("logger_status"),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Page 4: GPS + Altitude + Speed
    function _drawGpsAlt(dc as Graphics.Dc, w as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 30, Graphics.FONT_SMALL, "GPS & ALTITUDE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 65, w - 20, 65);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 80, Graphics.FONT_XTINY, "LATITUDE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var latStr = (_gpsLat != null) ? _gpsLat.format("%.5f") + " deg" : "--";
        dc.drawText(w/2, 105, Graphics.FONT_SMALL, latStr, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 160, Graphics.FONT_XTINY, "LONGITUDE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var lonStr = (_gpsLon != null) ? _gpsLon.format("%.5f") + " deg" : "--";
        dc.drawText(w/2, 185, Graphics.FONT_SMALL, lonStr, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 235, w - 20, 235);

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 250, Graphics.FONT_XTINY, "ALTITUDE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 275, Graphics.FONT_SMALL, _fmt(_altitude) + " m", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 325, w - 20, 325);

        var speedStr = (_speed != null) ? (_speed * 3.6).format("%.1f") + " km/h" : "-- km/h";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 340, Graphics.FONT_SMALL, speedStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // 5 page dots
    function _drawDots(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var dotY    = h - 15;
        var spacing = 14;
        var startX  = w / 2 - (spacing * 2);
        for (var i = 0; i < 5; i++) {
            if (i == _page) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(startX + i * spacing, dotY, 5);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(startX + i * spacing, dotY, 3);
            }
        }
    }

    function _fmt(val) as String {
        if (val == null) { return "--"; }
        if (val instanceof Lang.Float || val instanceof Lang.Double) {
            return val.format("%.1f");
        }
        return val.toString();
    }

}
