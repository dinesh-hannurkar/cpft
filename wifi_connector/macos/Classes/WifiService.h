#import <Foundation/Foundation.h>

@interface WifiService : NSObject

- (NSArray<NSString *> *)scanNetworks;
- (BOOL)connectWithSSID:(NSString *)ssid password:(NSString *)password;
- (void)disconnect;

@end
