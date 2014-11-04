// ///////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2010, Frank Blumenberg
//
// See License.txt for complete licensing and attribution information.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// ///////////////////////////////////////////////////////////////////////////////


#import "MKBluetoothConnection.h"
#import "MKBTStackManager.h"
#import <CocoaLumberjack/CocoaLumberjack.h>

static NSString *const MKBluetoothConnectionException = @"MKBluetoothConnectionException";

@interface MKBluetoothConnection ()

- (void)didDisconnect;
- (void)didConnect;
- (void)didDisconnectWithError:(int)err;
- (void)setAddressFromString:(NSString *)addressString;

- (NSString *)stringForAddress;

@end

///////////////////////////////////////////////////////////////////////////////
#pragma mark - DDRegisteredDynamicLogging
static int ddLogLevel = LOG_LEVEL_WARN;

@interface MKBluetoothConnection (DDRegisteredDynamicLogging) <DDRegisteredDynamicLogging>
@end

@implementation MKBluetoothConnection (DDRegisteredDynamicLogging)
+ (int)ddLogLevel {
  return ddLogLevel;
}

+ (void)ddSetLogLevel:(int)logLevel {
  ddLogLevel = logLevel;
}
@end
///////////////////////////////////////////////////////////////////////////////


@implementation MKBluetoothConnection

#pragma mark Properties

@synthesize delegate;
@synthesize mkData;


//////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Initialization

- (id)init {
  return [self initWithDelegate:nil];
}

- (id)initWithDelegate:(id <MKConnectionDelegate>)theDelegate; {
  self = [super init];
  if (self) {

    btManager = [MKBTStackManager sharedInstance];
    btManager.delegate = nil;

    self.delegate = theDelegate;

    memset(_address, 0, sizeof(bd_addr_t));

  }
  return self;
}

- (void)dealloc {
  self.mkData = nil;
  [super dealloc];
}

//////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark MKInput


- (void)didDisconnect {

  int err = bt_close();
  DDLogInfo(@"bt_close called with retval %d", err);

  opened = NO;

  if ([delegate respondsToSelector:@selector(didDisconnect)]) {
    [delegate didDisconnect];
  }

  btManager.delegate = nil;
}

- (void)didConnect {


  if ([delegate respondsToSelector:@selector(didConnectTo:)]) {
    [delegate didConnectTo:[self stringForAddress]];
  }
}

- (void)didDisconnectWithError:(int)err {

  int retval = bt_close();
  DDLogInfo(@"bt_close called with retval %d", retval);

  opened = NO;

  if ([delegate respondsToSelector:@selector(willDisconnectWithError:)]) {
    [delegate willDisconnectWithError:[NSError errorWithDomain:@"de.frankblumenberg.ikopter" code:err userInfo:nil]];
  }

  btManager.delegate = nil;
}

//////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -

- (BOOL)connectTo:(NSDictionary *)connectionInfo; {
  if (delegate == nil) {
    [NSException raise:MKBluetoothConnectionException
                format:@"Attempting to connect without a delegate. Set a delegate first."];
  }

  NSString* address = [connectionInfo objectForKey:kKConnectionInfoAddress];
  NSString* extra = [connectionInfo objectForKey:kKConnectionInfoExtra];
  
  DDLogInfo(@"Try to connect to %@", address);

  if ([extra length] > 0)
    [extra getCString:pin maxLength:17 encoding:NSISOLatin1StringEncoding];
  else {
    DDLogInfo(@"No PIN set for device, default to 0000");
    strcpy(pin, "0000");
  }

  [self setAddressFromString:address];
  self.mkData = [NSMutableData dataWithCapacity:512];

  if (bt_open() != 0) {
    DDLogWarn(@"bt_open failed. Maybe no BTStack installed");
    [self didDisconnectWithError:-1];
  }
  opened = YES;

  btManager.delegate = self;

  bt_send_cmd(&btstack_set_power_mode, HCI_POWER_ON);
  DDLogInfo(@"Did connect to %@", address);

  return YES;
}

- (BOOL)isConnected; {
  return opened;
}

- (void)disconnect; {
  if ([self isConnected]) {
    DDLogInfo(@"Try to disconnect from %@", [self stringForAddress]);

    DDLogVerbose(@"Send RFCOMM disconnect");
    bt_send_cmd(&rfcomm_disconnect, rfcomm_channel_id, 0);
    DDLogVerbose(@"Send deactivate");
    bt_send_cmd(&btstack_set_power_mode, HCI_POWER_OFF);
  }

  [self didDisconnect];
}

- (void)writeMkData:(NSData *)data; {
  if ([self isConnected])
    bt_send_rfcomm(rfcomm_channel_id, (uint8_t *) [data bytes], [data length]);
}

//////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -

- (void)btReadData:(uint8_t *)packet withLen:(uint16_t)size {
  NSData *data = [NSData dataWithBytes:packet length:size];
  if ([data length] > 0) {

    /*
    * The new data, which may only be partial, gets appended to the previously
    * collected buffer in self.mkData.
    * Then a line delimiter is searched, and any complete lines are passed
    * to the delegate, and removed from the local buffer in self.mkData.
    * We repeat this search for lines until no more are found.
    */

    [self.mkData appendData:data];

    Boolean again;
    do {
      again = false;

      const char *haystackBytes = [self.mkData bytes];
      static char needle = '\r';

      for (int i = 0; i < [self.mkData length]; i++) {
        if (haystackBytes[i] == needle) { // check for line delimiter

          // extract the line
          NSRange r = {0, i + 1};
          NSData *cmdData = [self.mkData subdataWithRange:r];

          // remove the line from the receive buffer
          [self.mkData replaceBytesInRange:r withBytes:NULL length:0];

          if ([delegate respondsToSelector:@selector(didReadMkData:)]) {
            [delegate didReadMkData:cmdData];
          }
          again = true; // see if there are more lines to process
          break;
        }
      }
    } while (again);

  }
}


- (NSString *)stringForAddress {
  return [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x", _address[0], _address[1], _address[2],
                                    _address[3], _address[4], _address[5]];
}

- (void)setAddressFromString:(NSString *)addressString {

  // support both : and - or NOTHING as separator
  addressString = [addressString stringByReplacingOccurrencesOfString:@":" withString:@""];
  addressString = [addressString stringByReplacingOccurrencesOfString:@"-" withString:@""];
  if ([addressString length] != 12) return;

  unsigned int bd_addr_buffer[BD_ADDR_LEN];  //for sscanf, integer needed
  // reset result buffer
  int i;
  for (i = 0; i < BD_ADDR_LEN; i++) {
    bd_addr_buffer[i] = 0;
  }

  // parse
  int result = sscanf([addressString UTF8String], "%2x%2x%2x%2x%2x%2x", &bd_addr_buffer[0], &bd_addr_buffer[1], &bd_addr_buffer[2],
          &bd_addr_buffer[3], &bd_addr_buffer[4], &bd_addr_buffer[5]);
  // store
  if (result == 6) {
    for (i = 0; i < BD_ADDR_LEN; i++) {
      _address[i] = (uint8_t) bd_addr_buffer[i];
    }
  }
}

//////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -

- (void)btstackManager:(MKBTStackManager *)manager
  handlePacketWithType:(uint8_t)packet_type
            forChannel:(uint16_t)channel
               andData:(uint8_t *)packet
               withLen:(uint16_t)size {
  bd_addr_t event_addr;

  switch (packet_type) {

    case RFCOMM_DATA_PACKET:
      DDLogVerbose(@"Received RFCOMM data on channel id %u, size %u", channel, size);
      //hexdump(packet, size);
      [self btReadData:packet withLen:size];
      break;

    case HCI_EVENT_PACKET:
      switch (packet[0]) {

        case BTSTACK_EVENT_POWERON_FAILED:
          // handle HCI init failure
          DDLogVerbose(@"HCI Init failed - make sure you have turned off Bluetooth in the System Settings");
          [self didDisconnectWithError:-1];
          break;

        case BTSTACK_EVENT_STATE:
          // bt stack activated, get started
          if (packet[2] == HCI_STATE_WORKING) {
            DDLogVerbose(@"BTStack is activated, start RFCOMM connection");
            bt_send_cmd(&rfcomm_create_channel, _address, 1);

//            [self performSelector:@selector(disconnect) withObject:self afterDelay:30.0];
          }
          break;

        case HCI_EVENT_PIN_CODE_REQUEST:
          // inform about pin code request
          DDLogVerbose(@"Using PIN 0000");
          bt_flip_addr(event_addr, &packet[2]);
          bt_send_cmd(&hci_pin_code_request_reply, &event_addr, strlen(pin), pin);
          break;

        case RFCOMM_EVENT_OPEN_CHANNEL_COMPLETE:
          // data: event(8), len(8), status (8), address (48),              server channel(8), rfcomm_cid(16), max frame size(16)
          // data: event(8), len(8), status (8), address (48), handle (16), server channel(8), rfcomm_cid(16), max frame size(16)
          if (packet[2]) {
            DDLogVerbose(@"RFCOMM channel open failed, status %u", packet[2]);
            [self didDisconnectWithError:packet[2]];
          } else {
            rfcomm_channel_id = READ_BT_16(packet, 12);
            int16_t mtu = READ_BT_16(packet, 14);
            DDLogVerbose(@"RFCOMM channel open succeeded. New RFCOMM Channel ID %u, max frame size %u", rfcomm_channel_id, mtu);
            [self didConnect];
          }
          break;

        case HCI_EVENT_DISCONNECTION_COMPLETE:
          // connection closed -> quit test app
          DDLogVerbose(@"Basebank connection closed");
          [self didDisconnect];
          break;

        default:
          DDLogVerbose(@"Unhandled HCI_EVENT_PACKET packet with event %d for channel %d", packet[0], channel);
          break;
      }
      break;
    default:
      DDLogVerbose(@"Unhandled packet with type %d for channel %d", packet_type, channel);
      break;
  }
}


@end
