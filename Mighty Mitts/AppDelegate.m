//
//  AppDelegate.m
//  Mighty Mitts
//
//  Created by Phillip Tennen on 10/03/2024.
//

#import "AppDelegate.h"
#import <CoreBluetooth/CoreBluetooth.h>

// Ref: https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/Assigned_Numbers.pdf?v=1710192432890
#define BT_BATTERY_SERVICE_UUID @"0x180F"
#define BT_BATTERY_LEVEL_CHARACTERISTIC @"0x2A19"

// Device Information service, and the characteristics we display
#define BT_DEVICE_INFO_SERVICE_UUID @"0x180A"
#define BT_PNP_ID_CHARACTERISTIC @"0x2A50"

#define LAST_KEYBOARD_DEFAULTS_KEY @"LastSelectedKeyboardIdentifier"

// How often we should ping the keyboard for updates, in seconds
#define BATTERY_LEVEL_FETCH_INTERVAL_SECONDS 60

@interface AppDelegate () <CBCentralManagerDelegate, CBPeripheralDelegate, NSMenuDelegate>
@property (nonatomic, retain) NSStatusItem* menuIcon;
@property (nonatomic, retain) NSTimer* updateTimer;
@property (nonatomic, retain) CBCentralManager* bluetoothManager;
@property (nonatomic, retain) CBPeripheral* selectedKeyboardPeripheral;
@property (nonatomic, retain) NSArray<CBPeripheral*>* availablePeripherals;
// Details about the selected peripheral, keyed by characteristic UUID string (from the Device Information service)
@property (nonatomic, retain) NSMutableDictionary<NSString*, NSString*>* deviceInfo;
@property (nonatomic, retain) NSNumber* signalStrength;
@property int leftKeyboardBatteryPercent;
@property int rightKeyboardBatteryPercent;
// PT: Quick hack to know whether this is the battery reading for the left or right side:
// In my testing, this callback is always invoked with the left half's battery reading first, then the right half's.
// So, just use flip flop state to track whether the current reading is for the left or right half.
// This is obviously not rigorous, but has worked fine in my testing and I'm not sure of a better way offhand.
@property BOOL isNextUpdateForRightHalf;
@end

@implementation AppDelegate

- (void)updateMenuButtonText {
    self.menuIcon.button.title = [NSString stringWithFormat:@"%i%%  %i%%", self.leftKeyboardBatteryPercent, self.rightKeyboardBatteryPercent];
    // PT: I've found in practice that I need to set up the border each time I  update the button's title.
    // I assume, but haven't confirmed, that reassigning the button's title creates an entirely new button.
    self.menuIcon.button.layer.borderWidth = 0.8;
    self.menuIcon.button.layer.borderColor = [[NSColor blackColor] CGColor];
    self.menuIcon.button.layer.cornerRadius = 4.0;
}

- (void)deselectPreviousPeripheral {
    self.selectedKeyboardPeripheral = nil;
    self.deviceInfo = [NSMutableDictionary dictionary];
    self.signalStrength = nil;
    self.leftKeyboardBatteryPercent = 0;
    self.rightKeyboardBatteryPercent = 0;
    self.isNextUpdateForRightHalf = NO;
}

- (void)highlightSelectedPeripheralMenuButton {
    // Update the dropdown menu so that the peripheral that's just been selected has a checkmark, and nothing else has a checkmark
    // (We'll also implicitly deselect any peripheral that was previously selected).
    for (NSMenuItem* item in self.menuIcon.menu.itemArray) {
        CBPeripheral* itemPeripheral = item.representedObject;
        if (itemPeripheral && self.selectedKeyboardPeripheral && [itemPeripheral.identifier isEqual:self.selectedKeyboardPeripheral.identifier]) {
            item.state = NSControlStateValueOn;
        }
        else {
            item.state = NSControlStateValueOff;
        }
    }
}

- (void)selectPeripheral:(CBPeripheral*)peripheral {
    // Clear out any state from a previously selected peripheral
    [self deselectPreviousPeripheral];
    
    if (!peripheral) {
        return;
    }
    self.selectedKeyboardPeripheral = peripheral;
    NSLog(@"Selected keyboard peripheral: %@", self.selectedKeyboardPeripheral.name);
    self.selectedKeyboardPeripheral.delegate = self;
    // 'Connect' to the peripheral within the context of this app, so we can read the battery level (though the peripheral is already connected to this Mac)
    [self.bluetoothManager connectPeripheral:self.selectedKeyboardPeripheral options:nil];
    [self highlightSelectedPeripheralMenuButton];
}

- (void)peripheralButtonClicked:(NSMenuItem*)sender {
    CBPeripheral* peripheral = sender.representedObject;
    if (!peripheral) {
        return;
    }
    // Remember the choice, so we can auto-select this keyboard if it disappears and comes back (or after a relaunch)
    [[NSUserDefaults standardUserDefaults] setObject:peripheral.identifier.UUIDString forKey:LAST_KEYBOARD_DEFAULTS_KEY];
    [self selectPeripheral:peripheral];
}

- (void)restoreLastSelectedPeripheralIfNeeded {
    if (self.selectedKeyboardPeripheral) {
        return;
    }
    NSString* savedId = [[NSUserDefaults standardUserDefaults] stringForKey:LAST_KEYBOARD_DEFAULTS_KEY];
    NSUUID* uuid = savedId ? [[NSUUID alloc] initWithUUIDString:savedId] : nil;
    if (!uuid) {
        return;
    }
    // This works even if the keyboard isn't currently connected; the pending connect completes when it returns
    CBPeripheral* peripheral = [[self.bluetoothManager retrievePeripheralsWithIdentifiers:@[uuid]] firstObject];
    if (peripheral) {
        NSLog(@"Auto-selecting previously chosen keyboard: %@", peripheral.name);
        [self selectPeripheral:peripheral];
    }
}

- (NSMenu*)buildDetailsSubmenu {
    CBPeripheral* peripheral = self.selectedKeyboardPeripheral;
    NSMenu* submenu = [[NSMenu alloc] init];
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    void (^add)(NSString*, NSString*) = ^(NSString* label, NSString* value) {
        if (value.length > 0) {
            [lines addObject:[NSString stringWithFormat:@"%@: %@", label, value]];
        }
    };
    NSString* stateName = @"Disconnected";
    if (peripheral.state == CBPeripheralStateConnected) stateName = @"Connected";
    else if (peripheral.state == CBPeripheralStateConnecting) stateName = @"Connecting";
    add(@"Name", peripheral.name);
    add(@"State", stateName);
    add(@"Signal", self.signalStrength ? [NSString stringWithFormat:@"%@ dBm", self.signalStrength] : nil);
    add(@"Manufacturer", self.deviceInfo[@"2A29"]);
    add(@"Model", self.deviceInfo[@"2A24"]);
    add(@"Serial", self.deviceInfo[@"2A25"]);
    add(@"Firmware", self.deviceInfo[@"2A26"]);
    add(@"Hardware", self.deviceInfo[@"2A27"]);
    add(@"Software", self.deviceInfo[@"2A28"]);
    add(@"Vendor / Product ID", self.deviceInfo[@"2A50"]);
    add(@"Identifier", peripheral.identifier.UUIDString);
    for (NSString* line in lines) {
        // No action, so these show as informational (greyed) rows
        [submenu addItemWithTitle:line action:nil keyEquivalent:@""];
    }
    return submenu;
}

- (void)refreshAvailablePeripherals {
    [self restoreLastSelectedPeripheralIfNeeded];
    // Rebuild the contents of the (persistent) dropdown menu each time we read the available peripherals
    NSMenu* dropdown = self.menuIcon.menu;
    if (!dropdown) {
        dropdown = [[NSMenu alloc] init];
        dropdown.autoenablesItems = YES;
        dropdown.delegate = self;
        self.menuIcon.menu = dropdown;
    }
    [dropdown removeAllItems];
    
    // Bold title view, drawn directly with a text view as the 'section headers' provided by NSMenu were a bit too gray for a call to action
    NSMenuItem* title = [[NSMenuItem alloc] init];
    NSTextField* titleTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 20)];
    titleTextField.bezeled = NO;
    titleTextField.drawsBackground = NO;
    titleTextField.editable = NO;
    titleTextField.selectable = NO;
    titleTextField.stringValue = @"Select Your Keyboard";
    titleTextField.font = [NSFont boldSystemFontOfSize:12];
    titleTextField.alignment = NSTextAlignmentCenter;
    title.view = titleTextField;
    [dropdown addItem:title];
    
    // Create a button corresponding to each connected peripheral that exposes the BLE Battery Service
    NSArray<CBUUID*>* serviceUuids = @[[CBUUID UUIDWithString:BT_BATTERY_SERVICE_UUID]];
    NSMutableArray<CBPeripheral*>* peripherals = [[self.bluetoothManager retrieveConnectedPeripheralsWithServices:serviceUuids] mutableCopy];
    // A keyboard that's momentarily disconnected (e.g. asleep) isn't reported as connected by the system.
    // Keep our selected keyboard in the list so it doesn't vanish, and so we keep trying to reconnect to it.
    CBPeripheral* selected = self.selectedKeyboardPeripheral;
    if (selected) {
        BOOL alreadyListed = NO;
        for (CBPeripheral* p in peripherals) {
            if ([p.identifier isEqual:selected.identifier]) { alreadyListed = YES; break; }
        }
        if (!alreadyListed) {
            [peripherals addObject:selected];
        }
    }
    for (CBPeripheral* p in peripherals) {
        NSString* peripheralTitle = p.name ?: [NSString stringWithFormat:@"Unnamed keyboard (%@)", [p.identifier.UUIDString substringToIndex:8]];
        NSMenuItem* item = [dropdown addItemWithTitle:peripheralTitle action:@selector(peripheralButtonClicked:) keyEquivalent:@""];
        item.representedObject = p;
    }
    if (peripherals.count == 0) {
        NSMenuItem* none = [dropdown addItemWithTitle:@"No keyboards found" action:nil keyEquivalent:@""];
        none.enabled = NO;
    }
    // And cache all the peripherals that we saw, so we can map the button press back to a peripheral once the user makes a selection
    self.availablePeripherals = peripherals;
    
    // Add some extra meta controls to the menu
    [dropdown addItem:[NSMenuItem  separatorItem]];
    if (self.selectedKeyboardPeripheral) {
        NSMenuItem* detailsItem = [dropdown addItemWithTitle:@"Device Details" action:nil keyEquivalent:@""];
        detailsItem.submenu = [self buildDetailsSubmenu];
    }
    [dropdown addItemWithTitle:@"Manually Refresh Battery" action:@selector(initiateBatteryReading) keyEquivalent:@""];
    [dropdown addItemWithTitle:@"Refresh Devices List" action:@selector(refreshAvailablePeripherals) keyEquivalent:@""];
    [dropdown addItem:[NSMenuItem  separatorItem]];
    [dropdown addItemWithTitle:@"Quit" action:@selector(quitButtonClicked) keyEquivalent:@""];
    
    // Ensure any selected peripheral still has the checkmark in the newly constructed menu
    [self highlightSelectedPeripheralMenuButton];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    // Always show a fresh devices list when the user opens the menu
    if (self.bluetoothManager.state == CBManagerStatePoweredOn) {
        [self refreshAvailablePeripherals];
    }
}

- (void)quitButtonClicked {
    NSLog(@"Quit button clicked, exiting now.");
    exit(0);
}

- (void)initiateBatteryReading {
    // Also pick up the Device Information service, and signal strength, for the details submenu
    [self.selectedKeyboardPeripheral discoverServices:@[[CBUUID UUIDWithString:BT_BATTERY_SERVICE_UUID],
                                                        [CBUUID UUIDWithString:BT_DEVICE_INFO_SERVICE_UUID]]];
    if (self.selectedKeyboardPeripheral.state == CBPeripheralStateConnected) {
        [self.selectedKeyboardPeripheral readRSSI];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Set up Bluetooth
    self.bluetoothManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];

    // Initialize the status bar icon
    self.menuIcon = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.menuIcon.button.title = @"No keyboard selected.";
    
    // Periodic job to refresh the UI / kick the tires
    self.updateTimer = [NSTimer timerWithTimeInterval:BATTERY_LEVEL_FETCH_INTERVAL_SECONDS repeats:YES block:^(NSTimer* timer){
        if (self.bluetoothManager.state == CBManagerStatePoweredOn) {
            [self refreshAvailablePeripherals];
        }
        if (!self.selectedKeyboardPeripheral) {
            self.menuIcon.button.title = @"No keyboard selected.";
        }
        else if (self.selectedKeyboardPeripheral.state == CBPeripheralStateDisconnected) {
            self.menuIcon.button.title = @"Disconnected.";
            // Try to reconnect
            [self.bluetoothManager connectPeripheral:self.selectedKeyboardPeripheral options:nil];
        }
        else if (self.selectedKeyboardPeripheral.state == CBPeripheralStateConnecting) {
            self.menuIcon.button.title = @"Connecting...";
        }
        else if (self.selectedKeyboardPeripheral.state == CBPeripheralStateConnected) {
            [self initiateBatteryReading];
        }
    }];
    [[NSRunLoop currentRunLoop] addTimer:self.updateTimer forMode:NSDefaultRunLoopMode];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state == CBManagerStatePoweredOn) {
        [self refreshAvailablePeripherals];
    }
    else {
        // In any other Bluetooth state, clear our saved BT peripheral as it's irrelevant
        [self deselectPreviousPeripheral];
        self.menuIcon.button.title = @"Bluetooth unavailable.";
    }
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"Disconnected from peripheral: %@ (%@)", peripheral.name, error);
    if ([peripheral.identifier isEqual:self.selectedKeyboardPeripheral.identifier]) {
        self.menuIcon.button.title = @"Disconnected.";
        // Pending connects don't time out, so this will complete whenever the keyboard comes back
        [self.bluetoothManager connectPeripheral:peripheral options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"Failed to connect to peripheral: %@ (%@)", peripheral.name, error);
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"Connected to peripheral: %@", peripheral.name);
    // Now that we're connected to the keyboard we'll be able to read its battery levels
    // Invoke main refresh task, which will kick this off.
    [self.updateTimer fire];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    for (CBService *service in peripheral.services) {
        if ([service.UUID isEqual:[CBUUID UUIDWithString:BT_BATTERY_SERVICE_UUID]]) {
            [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:BT_BATTERY_LEVEL_CHARACTERISTIC]] forService:service];
        }
        else if ([service.UUID isEqual:[CBUUID UUIDWithString:BT_DEVICE_INFO_SERVICE_UUID]]) {
            [peripheral discoverCharacteristics:nil forService:service];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if ([service.UUID isEqual:[CBUUID UUIDWithString:BT_BATTERY_SERVICE_UUID]]) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:BT_BATTERY_LEVEL_CHARACTERISTIC]]) {
                [peripheral readValueForCharacteristic:characteristic];
            }
        }
    }
    else if ([service.UUID isEqual:[CBUUID UUIDWithString:BT_DEVICE_INFO_SERVICE_UUID]]) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            if (characteristic.properties & CBCharacteristicPropertyRead) {
                [peripheral readValueForCharacteristic:characteristic];
            }
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error {
    if (!error) {
        self.signalStrength = RSSI;
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (!error && [characteristic.service.UUID isEqual:[CBUUID UUIDWithString:BT_DEVICE_INFO_SERVICE_UUID]] && characteristic.value) {
        NSString* text = nil;
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:BT_PNP_ID_CHARACTERISTIC]]) {
            // PnP ID layout: vendor ID source (1 byte), vendor ID (2), product ID (2), product version (2), little endian
            if (characteristic.value.length >= 7) {
                const uint8_t* b = characteristic.value.bytes;
                text = [NSString stringWithFormat:@"0x%04X / 0x%04X", b[1] | (b[2] << 8), b[3] | (b[4] << 8)];
            }
        }
        else {
            text = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
        }
        if (text) {
            self.deviceInfo[characteristic.UUID.UUIDString] = text;
        }
        return;
    }
    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:BT_BATTERY_LEVEL_CHARACTERISTIC]]) {
        uint8_t batteryLevel = 0;
        [characteristic.value getBytes:&batteryLevel length:sizeof(batteryLevel)];

        NSString* keyboardHalfName = self.isNextUpdateForRightHalf ? @"right" : @"left";
        NSLog(@"Retrieved battery level for %@ half of keyboard peripheral \"%@\": %d%%", keyboardHalfName, peripheral.name, batteryLevel);
        
        // Update our modelling of the keyboard state
        if (self.isNextUpdateForRightHalf) {
            self.rightKeyboardBatteryPercent = batteryLevel;
        }
        else {
            self.leftKeyboardBatteryPercent = batteryLevel;
        }
        
        // Update the UI
        [self updateMenuButtonText];
        
        // Flip our flip-flop so we're ready for the next callback invocation
        self.isNextUpdateForRightHalf = !self.isNextUpdateForRightHalf;
    }
}

@end
