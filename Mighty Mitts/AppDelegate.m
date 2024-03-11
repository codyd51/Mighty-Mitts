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

// Set this to the peripheral name to search for
#define KEYBOARD_BT_NAME @"Phillip's Asweep"
// How often we should ping the keyboard for updates, in seconds
#define BATTERY_LEVEL_FETCH_INTERVAL_SECONDS 60

@interface AppDelegate () <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, retain) NSStatusItem* menuIcon;
@property (nonatomic, retain) NSTimer* updateTimer;
@property (nonatomic, strong) CBCentralManager* bluetoothManager;
@property (nonatomic, retain) CBPeripheral* keyboardPeripheral;
@property int leftKeyboardBatteryPercent;
@property int rightKeyboardBatteryPercent;
@end

@implementation AppDelegate

- (void)updateMenuButtonText {
    self.menuIcon.button.title = [NSString stringWithFormat:@"L: %i%%    R: %i%%", self.leftKeyboardBatteryPercent, self.rightKeyboardBatteryPercent];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Set up Bluetooth
    self.bluetoothManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];

    // Initialize the status bar icon
    self.menuIcon = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.menuIcon.button.title = @"Searching...";
    
    // Periodic job to refresh the UI / kick the tires
    self.updateTimer = [NSTimer timerWithTimeInterval:BATTERY_LEVEL_FETCH_INTERVAL_SECONDS repeats:YES block:^(NSTimer* timer){
        if (!self.keyboardPeripheral) {
            self.menuIcon.button.title = @"No keyboard found.";
        }
        else if (self.keyboardPeripheral.state == CBPeripheralStateDisconnected) {
            self.menuIcon.button.title = @"Disconnected.";
            // Try to reconnect
            [self.bluetoothManager connectPeripheral:self.keyboardPeripheral options:nil];
        }
        else if (self.keyboardPeripheral.state == CBPeripheralStateConnecting) {
            self.menuIcon.button.title = @"Connecting...";
        }
        else if (self.keyboardPeripheral.state == CBPeripheralStateConnected) {
            [self.keyboardPeripheral discoverServices:@[[CBUUID UUIDWithString:BT_BATTERY_SERVICE_UUID]]];
        }
    }];
    [[NSRunLoop currentRunLoop] addTimer:self.updateTimer forMode:NSDefaultRunLoopMode];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state == CBManagerStatePoweredOn) {
        NSArray<CBUUID*>* serviceUuids = @[[CBUUID UUIDWithString:BT_BATTERY_SERVICE_UUID]];
        NSArray<CBPeripheral*>* peripherals = [self.bluetoothManager retrieveConnectedPeripheralsWithServices:serviceUuids];
        NSArray<CBPeripheral*>* foundPeripherals = [peripherals filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
            return [((CBPeripheral*)evaluatedObject).name isEqualToString:KEYBOARD_BT_NAME];
        }]];
        if (foundPeripherals.count >= 1) {
            self.keyboardPeripheral = foundPeripherals[0];
            NSLog(@"Found keyboard peripheral: %@", self.keyboardPeripheral.name);
            self.keyboardPeripheral.delegate = self;
            // 'Connect' to it so we can read the battery level (though the keyboard is probably already connected to this Mac)
            [self.bluetoothManager connectPeripheral:self.keyboardPeripheral options:nil];
        }
    } 
    else {
        // In any other Bluetooth state, just clear our saved BT peripheral as it's irrelevant
        self.keyboardPeripheral = nil;
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
    // PT: Quick hack to know whether this is the battery reading for the left or right side:
    // In my testing, this callback is always invoked with the left half's battery reading first, then the right half's.
    // So, just use flip flop state to track whether the current reading is for the left or right half.
    // This is obviously not rigorous, but has worked fine in my testing and I'm not sure of a better way offhand.
    static BOOL isRight = NO;

    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:BT_BATTERY_LEVEL_CHARACTERISTIC]]) {
        uint8_t batteryLevel = 0;
        [characteristic.value getBytes:&batteryLevel length:sizeof(batteryLevel)];

        NSString* keyboardHalfName = isRight ? @"right" : @"left";
        NSLog(@"Retrieved battery level for %@ half of keyboard peripheral \"%@\": %d%%", keyboardHalfName, peripheral.name, batteryLevel);
        
        // Update our modelling of the keyboard state
        if (isRight) {
            self.rightKeyboardBatteryPercent = batteryLevel;
        }
        else {
            self.leftKeyboardBatteryPercent = batteryLevel;
        }
        
        // Update the UI
        [self updateMenuButtonText];
        
        // Flip our flip-flop so we're ready for the next callback invocation
        isRight = !isRight;
    }
}

@end
