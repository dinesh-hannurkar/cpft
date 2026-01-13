#import "WifiService.h"
#import <CoreWLAN/CoreWLAN.h>

@implementation WifiService

- (NSArray<NSString *> *)scanNetworks {
    CWWiFiClient *client = [CWWiFiClient sharedWiFiClient];
    CWInterface *interface = [client interface];

    NSError *error = nil;
    NSSet<CWNetwork *> *networks = [interface scanForNetworksWithName:nil error:&error];

    if (error) {
        NSLog(@"Error scanning for networks: %@", error);
        return @[];
    }

    NSMutableArray<NSString *> *ssids = [NSMutableArray array];
    for (CWNetwork *network in networks) {
        [ssids addObject:network.ssid];
    }

    return ssids;
}

- (BOOL)connectWithSSID:(NSString *)ssid password:(NSString *)password {
    CWWiFiClient *client = [CWWiFiClient sharedWiFiClient];
    CWInterface *interface = [client interface];

    NSError *error = nil;
    NSSet<CWNetwork *> *networks = [interface scanForNetworksWithName:ssid error:&error];

    if (error) {
        NSLog(@"Error scanning for network with SSID %@: %@", ssid, error);
        return NO;
    }

    CWNetwork *targetNetwork = nil;
    for (CWNetwork *network in networks) {
        if ([network.ssid isEqualToString:ssid]) {
            targetNetwork = network;
            break;
        }
    }

    if (!targetNetwork) {
        NSLog(@"Network with SSID %@ not found", ssid);
        return NO;
    }


    BOOL success = [interface associateToNetwork:targetNetwork password:password error:&error];

    if (!success) {
        NSLog(@"Error connecting to network %@: %@", ssid, error);
    }

    return success;
}

- (void)disconnect {
    CWWiFiClient *client = [CWWiFiClient sharedWiFiClient];
    CWInterface *interface = [client interface];
    [interface disassociate];
}

@end
