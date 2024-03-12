## Mighty Mitts

macOS uses the BLE Battery Service, and specifically the Battery Level characteristic, to display the battery level of BLE accessories like wireless keyboards. 

![macOS BLE Battery Levels](./readme_images/macOS_ble_battery.png)

Some keyboards, however, come in two halves that house individual batteries. 

![Phillip's Aurora Sweep](./readme_images/asweep.png)

These keyboards, when running [zmk](https://zmk.dev), can be [configured](https://zmk.dev/docs/config/battery#peripheral-battery-monitoring) to expose _two_ Battery Level characteristics over the Battery Service to convey the battery states of each half. 

However, macOS's native Bluetooth management UI will only display the battery level of the primary half. 

Mighty Mitts is a small app that lives in the menu bar and shows the battery state of each keyboard half. 

![Mighty Mitts Menu Bar UI](./readme_images/mighty_mitts_ui_v2.png)
![Mighty Mitts Keyboard Selection UI](./readme_images/mighty_mitts_keyboard_selection.png)

MIT license.

