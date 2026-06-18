# TestingApplication — Garmin Connect IQ Sensor App
# Device: vivoactive6

## Project Structure (KEEP EXACTLY THIS — no subfolders)

```
TestingApplication/
├── manifest.xml
├── monkey.jungle
├── README.md
├── resources/
│   └── strings.xml
└── source/
    ├── TestingApplicationApp.mc
    ├── TestingApplicationView.mc
    └── TestingApplicationDelegate.mc
```

---

## How to Open in VS Code (Fresh Start)

1. Delete any old broken project folders
2. Copy this entire `TestingApplication/` folder to a simple path e.g. `D:\TestingApplication\`
3. Open VS Code
4. File → Open Folder → select `D:\TestingApplication\`
5. VS Code will detect the monkey.jungle automatically

---

## How to Generate Your Developer Key (one time only)

Press Ctrl+Shift+P → type:
  Monkey C: Generate Developer Key
Save it inside the project folder as `developer_key`

Then set it in VS Code settings:
  Ctrl+, → search "monkeyC" → set "Private Key Path" to:
  D:\TestingApplication\developer_key

---

## How to Build

Press Ctrl+Shift+P → type:
  Monkey C: Build for Device
Select: vivoactive6

Output: TestingApplication.prg in the project root

---

## How to Run in Simulator

Press Ctrl+Shift+P → type:
  Monkey C: Run No Tests
Select: vivoactive6

To see sensor logs: View → Show Console in the simulator

To simulate fake sensor data: Simulation → Sensors

---

## How to Add Another Device Later

1. Open manifest.xml
2. Add the device inside <iq:products>:

   <iq:products>
     <iq:product id="vivoactive6"/>
     <iq:product id="fenix7"/>        ← add like this
     <iq:product id="forerunner955"/> ← and this
   </iq:products>

3. Open monkey.jungle and add source paths for each device:

   project.manifest = manifest.xml

   vivoactive6.sourcePath = source
   vivoactive6.resourcePath = resources

   fenix7.sourcePath = source         ← add like this
   fenix7.resourcePath = resources

4. Download the device profile in SDK Manager → Devices tab
5. Rebuild — select the new device when prompted

---

## App Pages (tap screen to switch)

| Page | Content                        |
|------|--------------------------------|
| 0    | Heart Rate + Temperature       |
| 1    | Accelerometer X/Y/Z (milli-G)  |
| 2    | Gyroscope X/Y/Z (deg/sec)      |
| 3    | GPS Lat/Lon + Altitude + Speed |

All sensor data is recorded to a custom FIT file during activities.
Gyro values in FIT are stored x100 (divide by 100 when reading back).

---

## Sideload to Friend's Watch

1. Build → get TestingApplication.prg
2. Send the .prg file to your friend
3. Friend connects vivoactive6 via USB
4. Copy .prg to GARMIN/APPS/ on the watch
5. Start an activity on the watch → add data field → TestingApplication
