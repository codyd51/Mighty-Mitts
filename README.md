## Mighty Mitts

macOS uses the BLE Battery Service, and specifically the Battery Level characteristic, to display the battery level of BLE accessories like wireless keyboards. 

<img alt="macOS BLE Battery Levels" src="./readme_images/macOS_ble_battery.png" width="400">

Some keyboards, however, come in two halves that house individual batteries. 

<img alt="Phillip's Aurora Sweep" src="./readme_images/asweep.png" width="800">

These keyboards, when running [zmk](https://zmk.dev), can be [configured](https://zmk.dev/docs/config/battery#peripheral-battery-monitoring) to expose _two_ Battery Level characteristics over the Battery Service to convey the battery states of each half. 

However, macOS's native Bluetooth management UI will only display the battery level of the primary half. 

Mighty Mitts is a small app that lives in the menu bar and shows the battery state of each keyboard half. 

<img alt="Mighty Mitts Menu Bar UI" src="./readme_images/mighty_mitts_ui_v2.png" width="800">


<img alt="Mighty Mitts Keyboard Selection UI" src="./readme_images/mighty_mitts_keyboard_selection_v2.png" width="800">

### Running

Download, unzip, and double-click the [prebuilt release](https://github.com/codyd51/Mighty-Mitts/releases/tag/v2.0). 

Alternatively, open the project in Xcode, build, and run. 

### License 

MIT license.
