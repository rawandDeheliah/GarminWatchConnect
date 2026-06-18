// =============================================================
// TestingApplicationView.mc — Sensor Reading + Display
// Device: vivoactive6
//
// Reads and displays:
//   Heart Rate, Temperature  via setEnabledSensors
//   Accelerometer, Gyroscope via registerSensorDataListener
//   GPS, Altitude, Speed     via Position API
//
// Note: FIT recording via createField only works in DataField
// apps. This watch-app displays live sensor data on screen.
// =============================================================

import Toybox.WatchUi;
import Toybox.Sensor;
import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Position;
import Toybox.Lang;
import Toybox.System;

class TestingApplicationView extends WatchUi.View {

    // Sensor values
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

    // Pages: 0=HR+Temp | 1=Accel | 2=Gyro | 3=GPS+Alt
    var _page = 0;

    function initialize() {
        View.initialize();
        System.println("=== TestingApplication STARTED ===");
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // Standard 1Hz sensors
        Sensor.setEnabledSensors([
            Sensor.SENSOR_HEARTRATE,
            Sensor.SENSOR_TEMPERATURE
        ]);
        Sensor.enableSensorEvents(method(:onSensor));

        // High-frequency IMU via correct API
        var imuOptions = {
            :period        => 1,
            :accelerometer => { :enabled => true, :sampleRate => 25 },
            :gyroscope     => { :enabled => true, :sampleRate => 25 }
        };
        Sensor.registerSensorDataListener(method(:onSensorData), imuOptions);
        System.println("[INIT] IMU listener registered @ 25Hz");

        // GPS
        Position.enableLocationEvents(
            Position.LOCATION_CONTINUOUS,
            method(:onPosition)
        );
    }

    // ----------------------------------------------------------
    // Standard sensor callback ~1Hz (HR, Temp, Pressure)
    // ----------------------------------------------------------
    function onSensor(info as Sensor.Info) as Void {
        if (info has :heartRate && info.heartRate != null) {
            _heartRate = info.heartRate;
            System.println("[HR] " + _heartRate + " bpm");
        }
        if (info has :temperature && info.temperature != null) {
            _temperature = info.temperature;
            System.println("[TEMP] " + _temperature + " C");
        }
        if (info has :pressure && info.pressure != null) {
            _pressure = info.pressure;
            System.println("[PRESSURE] " + _pressure + " Pa");
        }
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    // High-frequency IMU callback
    // accelerometerData.x/y/z = Arrays of Float (milli-G)
    // gyroscopeData.x/y/z     = Arrays of Float (deg/sec)
    // ----------------------------------------------------------
    function onSensorData(sensorData as Sensor.SensorData) as Void {

        if (sensorData has :accelerometerData && sensorData.accelerometerData != null) {
            var a = sensorData.accelerometerData;
            if (a.x != null && a.x.size() > 0) {
                var i = a.x.size() - 1;
                _accelX = a.x[i];
                _accelY = a.y[i];
                _accelZ = a.z[i];
                System.println("[ACCEL] X=" + _accelX + " Y=" + _accelY + " Z=" + _accelZ);
            }
        }

        if (sensorData has :gyroscopeData && sensorData.gyroscopeData != null) {
            var g = sensorData.gyroscopeData;
            if (g.x != null && g.x.size() > 0) {
                var i = g.x.size() - 1;
                _gyroX = g.x[i];
                _gyroY = g.y[i];
                _gyroZ = g.z[i];
                System.println("[GYRO] X=" + _gyroX + " Y=" + _gyroY + " Z=" + _gyroZ);
            }
        }

        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    // GPS callback
    // ----------------------------------------------------------
    function onPosition(info as Position.Info) as Void {
        if (info.position != null) {
            var coords = info.position.toDegrees();
            _gpsLat = coords[0];
            _gpsLon = coords[1];
            System.println("[GPS] Lat=" + _gpsLat + " Lon=" + _gpsLon);
        }
        if (info has :altitude && info.altitude != null) {
            _altitude = info.altitude;
            System.println("[ALT] " + _altitude + " m");
        }
        if (info has :speed && info.speed != null) {
            _speed = info.speed;
            System.println("[SPEED] " + (_speed * 3.6).format("%.1f") + " km/h");
        }
        WatchUi.requestUpdate();
    }

    // Called from delegate on tap
    function nextPage() as Void {
        _page = (_page + 1) % 4;
        System.println("[UI] Page -> " + _page);
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

        if (_page == 0)      { _drawHRTemp(dc, w, h); }
        else if (_page == 1) { _drawAccel(dc, w, h);  }
        else if (_page == 2) { _drawGyro(dc, w, h);   }
        else                 { _drawGpsAlt(dc, w, h); }

        _drawDots(dc, w, h);
    }

    // Page 0: Heart Rate + Temperature
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

    // Page 1: Accelerometer
    function _drawAccel(dc as Graphics.Dc, w as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 30, Graphics.FONT_SMALL, "ACCELEROMETER", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 60, Graphics.FONT_XTINY, "milli-G  @ 25Hz", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 85, w - 20, 85);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 110, Graphics.FONT_MEDIUM, "X", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - 40, 110, Graphics.FONT_MEDIUM, _fmt(_accelX), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 200, Graphics.FONT_MEDIUM, "Y", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - 40, 200, Graphics.FONT_MEDIUM, _fmt(_accelY), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 290, Graphics.FONT_MEDIUM, "Z", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - 40, 290, Graphics.FONT_MEDIUM, _fmt(_accelZ), Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // Page 2: Gyroscope
    function _drawGyro(dc as Graphics.Dc, w as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 30, Graphics.FONT_SMALL, "GYROSCOPE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/2, 60, Graphics.FONT_XTINY, "deg/sec  @ 25Hz", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 85, w - 20, 85);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 110, Graphics.FONT_MEDIUM, "X", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - 40, 110, Graphics.FONT_MEDIUM, _fmt(_gyroX), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 200, Graphics.FONT_MEDIUM, "Y", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - 40, 200, Graphics.FONT_MEDIUM, _fmt(_gyroY), Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(40, 290, Graphics.FONT_MEDIUM, "Z", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - 40, 290, Graphics.FONT_MEDIUM, _fmt(_gyroZ), Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // Page 3: GPS + Altitude + Speed
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

    // 4 page dots
    function _drawDots(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var dotY = h - 20;
        var spacing = 16;
        var startX = w / 2 - (spacing * 1.5).toNumber();
        for (var i = 0; i < 4; i++) {
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
