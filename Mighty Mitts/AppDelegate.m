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

// How often we should ping the keyboard for updates, in seconds
#define BATTERY_LEVEL_FETCH_INTERVAL_SECONDS 60

@interface AppDelegate () <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, retain) NSStatusItem* menuIcon;
@property (nonatomic, retain) NSTimer* updateTimer;
@property (nonatomic, retain) CBCentralManager* bluetoothManager;
@property (nonatomic, retain) CBPeripheral* selectedKeyboardPeripheral;
@property (nonatomic, retain) NSArray<CBPeripheral*>* availablePeripherals;
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
    self.leftKeyboardBatteryPercent = 0;
    self.rightKeyboardBatteryPercent = 0;
    self.isNextUpdateForRightHalf = NO;
}

- (void)peripheralButtonClicked:(NSMenuItem*)sender {
    // Clear out any state from a previously selected peripheral
    [self deselectPreviousPeripheral];
    
    // Currently, we only have the title of the menu button that was clicked.
    // This should directly correspond to the name of one of the Bluetooth peripherals that we saw earlier, so pull out the
    // matching peripheral.
    NSArray<CBPeripheral*>* foundPeripherals = [self.availablePeripherals filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        return [((CBPeripheral*)evaluatedObject).name isEqualToString:sender.title];
    }]];
    if (foundPeripherals.count != 1) {
        // PT: Unfortunately we can't use +[NSException raise...] here, as AppKit catches exceptions thrown within a menu bar item callback.
        // Instead, present the error directly to the user, then exit.
        NSAlert* errorAlert = [[NSAlert alloc] init];
        errorAlert.messageText = @"Mighty Mitts Consistency Error";
        NSArray<NSString*>* matchedTitles = [foundPeripherals valueForKey:@"name"];
        errorAlert.informativeText = [NSString stringWithFormat:@"Expected to find exactly 1 peripheral in our cached connections list that matches the title of the pressed button (\"%@\"), but found: %@", sender.title, matchedTitles];
        [errorAlert addButtonWithTitle:@"Quit"];
        [errorAlert runModal];
        exit(1);
        // Just for semantics - we're no longer executing.
        return;
    }
    
    self.selectedKeyboardPeripheral = foundPeripherals[0];
    NSLog(@"Selected keyboard peripheral: %@", self.selectedKeyboardPeripheral.name);
    self.selectedKeyboardPeripheral.delegate = self;
    // 'Connect' to the peripheral within the context of this app, so we can read the battery level (though the peripheral is already connected to this Mac)
    [self.bluetoothManager connectPeripheral:self.selectedKeyboardPeripheral options:nil];
}

- (void)refreshAvailablePeripherals {
    // Discard and recreate the dropdown menu each time we read the available peripherals
    NSMenu* dropdown = [[NSMenu alloc] init];
    dropdown.autoenablesItems = YES;
    self.menuIcon.menu = dropdown;
    
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
    NSArray<CBPeripheral*>* peripherals = [self.bluetoothManager retrieveConnectedPeripheralsWithServices:serviceUuids];
    for (CBPeripheral* p in peripherals) {
        NSString* peripheralTitle = [NSString stringWithFormat:@"%@", p.name];
        NSMenuItem* peripheralButton = [[NSMenuItem alloc] initWithTitle:peripheralTitle action:@selector(peripheralButtonClicked:) keyEquivalent:peripheralTitle];
        [dropdown addItem:peripheralButton];
    }
    // And cache all the peripherals that we saw, so we can map the button press back to a peripheral once the user makes a selection
    self.availablePeripherals = peripherals;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Set up Bluetooth
    self.bluetoothManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];

    // Initialize the status bar icon
    self.menuIcon = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.menuIcon.button.title = @"No keyboard selected.";
    
    // Periodic job to refresh the UI / kick the tires
    self.updateTimer = [NSTimer timerWithTimeInterval:BATTERY_LEVEL_FETCH_INTERVAL_SECONDS repeats:YES block:^(NSTimer* timer){
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
            [self.selectedKeyboardPeripheral discoverServices:@[[CBUUID UUIDWithString:BT_BATTERY_SERVICE_UUID]]];
        }
    }];
    [[NSRunLoop currentRunLoop] addTimer:self.updateTimer forMode:NSDefaultRunLoopMode];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state == CBManagerStatePoweredOn) {
        [self refreshAvailablePeripherals];
    }
    else {
        // In any other Bluetooth state, just clear our saved BT peripheral as it's irrelevant
        self.selectedKeyboardPeripheral = nil;
    }
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
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
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
