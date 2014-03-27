# ZCRMailbox

[![Build Status](https://travis-ci.org/zradke/ZCRMailbox.svg?branch=master)](https://travis-ci.org/zradke/ZCRMailbox)

KVO subscription inspired by [FBKVOController](https://github.com/facebook/KVOController) and [MAKVONotificationCenter](https://github.com/mikeash/MAKVONotificationCenter), with compatibility back to iOS5.

===

## Requirements

You will need to have a minimum deployment target of iOS 5.0+ or OSX 10.7+, and be running under ARC, or know how to selectively enable ARC on specific files.

## Getting set up

Here's how to get ZCRMailbox up and running:

* Drag-n-drop
* Cocoapods
* Build a framework (iOS only)

Struggling in a sea of options? Allow me to strongly suggest using Cocoapods!

Regardless of which method you choose, you can start working with ZCRMailbox by importing it where you need:

```
#import "ZCRMailbox.h"
```

### Drag-n-drop

This project is really just two files: **ZCRMailbox.h** and **ZCRMailbox.m**. You can find them by cloning the repo and dragging them from the `Classes` directory into your Xcode project. Just make sure the "Copy items into destination group's folder (if needed)" checkbox is checked as well as whatever targets you need to use them in. Oh, and it's very unlikely, but if the names clash you may need to rename the files.

### Cocoapods

Need more info on Cocoapods? Check out their [website](http://cocoapods.org/) for more information on what its used for and how to get it running.

When you're done with that, or if you're already familiar with Cocoapods, just add

```
pod "ZCRMailbox"
```

to your `Podfile`, run `pod install` and you're good to go!

If you're working on a serious project, it's recommended to specify at least a major and minor version in your `Podfile`, ala: `pod "ZCRMailbox", "~> 0.1"`.

### Build a framework (iOS only)

Framework fan? Clone the repo and open the `Project/ZCRMailbox.xcodeproj` up in Xcode. Change the target to `Framework` and build. Navigate to the Organizer and in the "Projects" tab, locate the ZCRMailbox project. Click the minuscule arrow next to the "Derived Data" file path to open it in Finder. The correct folder should be highlighted and named something like `ZCRMailbox-<GOBBLEDYGOOK>`. Navigate into there then into `Build/Products/Release-<PLATFORM>` and finally you should see `ZCRMailbox.framework`. Phew.

Get a drink to celebrate, then drag the framework somewhere much easier to find.

Now that you have the packaged framework you can drag it into your projects, zip it up and ship it to friends, or just keep it around for fun.

===

## Putting it to use

### Creating a mailbox

Create a `ZCRMailbox` with a subscriber:

```
ZCRMailbox *mailbox = [[ZCRMailBox alloc] initWithSubscriber:subscriber]
```

Because the subscriber is only weakly referenced, it can be a good idea for the subscriber to keep hold of it's mailbox:

```
self.mailbox = [[ZCRMailbox alloc] initWithSubscriber:self];
```

If you need to deliver notifier messages to the subscriber on a specific queue, you can do that too:

```
self.mailbox.messageQueue = [NSOperationQueue mainQueue];
```

### Working with a mailbox

Once you have a mailbox you can start adding subscriptions to objects, called notifiers:

```
NSKeyValueObservingOptions options = NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew;
[self.mailbox subscribeTo:newsletter keyPath:@"updatedDate" options:options block:^(ZCRMessage *message) {
	// Do something
}];
```

You can add subscriptions to as many notifiers and key-paths as you'd like, all from one mailbox!

If you prefer selectors to blocks, give one of these a try:

```
[self.mailbox subscribeTo:newsletter keyPath:@"updatedDate" options:options selector:@selector(newsletterDidUpdateDate)];
[self.mailbox subscribeTo:newsletter keyPath:@"posts" options:options selector:@selector(newsletterDidUpdatePost:))];
...
- (void)newsletterDidUpdateDate { // Do stuff }
- (void)newsletterDidUpdatePost:(ZCRMessage *)message { // Do stuff }
```

Finally, if you are migrating traditional KVO code and want a quick plug-in solution until you can get selectors and blocks working, there's this:

```
static void *ABCSubscriberKVOContext = &ABCSubscriberKVOContext;
...
[self.mailbox subscribeTo:newsletter keyPath:@"updatedDate" options:options context:ABCSubscriberKVOContext];
...
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == ABCSubscriberKVOContext) {
        // Optionally convert this to a message
        ZCRMessage *message = [[ZCRMessage alloc] initWithNotifier:object keyPath:keyPath change:change];
        // Do something
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}
```

Not very pretty, but it'll do in a pinch. The context is optional, but traditionally a good idea to make sure the notification is the one you want to receive.

### Cleanup

When you're done with a mailbox, you can simply let it deallocate. This will automatically cancel all subscriptions.

If you need to unsubscribe but still want to work with the mailbox, you can use the unsubscribe methods:

```
[self.mailbox unsubscribeFrom:newsletter keyPath:@"updatedDate"];
[self.mailbox unsubscribeFrom:newsletter];
[self.mailbox unsubscribeFromAll];
```

===

## Testing

ZCRMailbox has unit tests using XCTest, and is continuously integrated using [Travis CI](https://travis-ci.org/zradke/ZCRMailbox). To run the tests yourself, first clone the repo. You can then either run the tests from within Xcode or from the command line.

#### Inside Xcode

Open up `Project/ZCRMailbox.xcodeproj` and make sure the scheme is set to "ZCRMailbox." Run the tests by selecting `Product/Test` from the top menu or using the shortcut `CMD+U`.

#### From the command line

First install [xctool](https://github.com/facebook/xctool). Then from within the project directory, run `rake test`.

## Deep-dive

Want more details on how the sausage gets made? This section will discuss some of the implementation details of ZCRMailbox.

### Architecture

* `ZCRMailbox` weakly references the subscriber and maintains a dictionary of strongly referenced notifiers as keys for sets of `_ZCRSubscription` objects
* `_ZCRSubscription` weakly references the `ZCRMailbox` that created it and other details about the KVO observation.
* To add and remove subscriptions, `ZCRMailbox` defers to the `_ZCRPostOffice` which is shared between all mailboxes.
* `_ZCRPostOffice` actually handles all KVO observation and observation-removal to ensure thread safety. It maintains a set of `_ZCRSubscription` objects sent by `ZCRMailbox` instances.

### Thread safety

* Simple `NSRecursiveLock` instances are used to maintain thread safety.
* Since all subscription is handled by the single locked `_ZCRPostOffice`, `ZCRMailbox` instances can be created, subscribe, and unsubscribe on different threads without having to worry.

### Performance

Because KVO subscription and un-subscription is expected to be synchronous, simple locking was used instead of a dispatch queue with multiple readers and a single writer. This would not be an issue if each `ZCRMailbox` actually handled its own KVO notifications, since an individual mailbox is not expected to receive a large volume of subscriptions or un-subscriptions. However, to prevent zombie KVO updates past the lifecycle of an observation, all updates are funneled through the shared `_ZCRPostOffice` which must synchronously handle all subscriptions. This can create a bottleneck if a large volume of subscriptions and un-subscriptions are occurring across all `ZCRMailbox` instances. The practical impact of this is unclear, but you are encouraged to profile these classes if you experience performance issues.



