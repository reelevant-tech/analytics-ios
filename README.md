# Reelevant Analytics SDK for iOS

This Swift package could be used to send tracking events to Reelevant datasources.

## How to use

You need to have a `datasourceId` and a `companyId` to be able to init the SDK and start sending events:

```swift
let config = ReelevantAnalytics.Configuration(companyId: "<company id>", datasourceId: "<datasource id>")
let sdk = ReelevantAnalytics.SDK(configuration: config)

// Generate an event
let event = ReelevantAnalytics.Event.page_view(labels: [:])
// Send it
sdk.send(event: event)
```

### Current URL

When a user is browsing a page you should call the `sdk.setCurrentURL` method if you want to be able to filter on it in Reelevant.

### User infos

To identify a user, you should call the `sdk.setUser("<user id>")` method which will store the user id in the device and send it to Reelevant.

### Labels

Each event type allow you to pass additional infos via `labels` (`Dictionary<String, String>`) on which you'll be able to filter in Reelevant.

```swift
let event = ReelevantAnalytics.Event.add_cart(ids: ["my-product-id"], labels: ["lang": "en_US"])
```

### Objective-C

The package is also compatible with objective-c apps:

```objective-c
#import "ViewController.h"
@import ReelevantAnalytics;

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (IBAction)myAction:(id)sender {
    Configuration *config = [[Configuration alloc] initWithCompanyId:@"foo" datasourceId:@"bar"];
    SDK *sdk = [[SDK alloc] initWithConfiguration:config];
    
    Event *event = [EventBuilder page_viewWithLabels:[[NSMutableDictionary alloc] init]];
    
    [sdk sendWithEvent:event];
}

@end
```
