//
//  ZCRMailboxTests.m
//  ZCRMailboxTests
//
//  Created by Zachary Radke on 3/20/14.
//  Copyright (c) 2014 Zach Radke. All rights reserved.
//

#import "ZCRMailbox.h"

@import XCTest;

@interface ZCRModel : NSObject
@property (strong, nonatomic) NSString *name;
@property (assign, nonatomic) NSUInteger identifier;
@property (assign) NSTimeInterval time;
@end

@implementation ZCRModel
@end

@interface ZCRSubscriber : NSObject
@property (strong, nonatomic) ZCRMailbox *mailbox;
@end

@implementation ZCRSubscriber
@end


@interface ZCRMailboxTests : XCTestCase {
    ZCRSubscriber *subscriber;
    ZCRModel *notifier;
    ZCRMailbox *mailbox;
}
@end

@implementation ZCRMailboxTests

- (void)setUp {
    [super setUp];
    
    subscriber = [ZCRSubscriber new];
    notifier = [ZCRModel new];
    mailbox = [[ZCRMailbox alloc] initWithSubscriber:subscriber];
}

- (void)tearDown {
    mailbox = nil;
    notifier = nil;
    subscriber = nil;
    
    [super tearDown];
}

- (void)testBasicSubscription {
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger timesInvoked = 0;
    __block ZCRMessage *lastMessage = nil;
    
    BOOL result = [mailbox subscribeTo:notifier keyPath:@"name" options:options block:^(ZCRMessage *message) {
        timesInvoked++;
        lastMessage = message;
    }];
    
    XCTAssertTrue(result, @"The subscription should be added");
    
    notifier.name = @"test01";
    
    XCTAssertTrue(timesInvoked == 1, @"The block should be invoked once.");
    XCTAssertEqualObjects(lastMessage.notifier, notifier, @"The notifiers should match.");
    XCTAssertNil(lastMessage.oldValue, @"There shouldn't be an old value");
    XCTAssertEqualObjects(lastMessage.newValue, @"test01", @"There should be a new value");
    
    notifier.name = @"test02";
    
    XCTAssertTrue(timesInvoked == 2, @"The block should be invoked twice.");
    XCTAssertEqualObjects(lastMessage.notifier, notifier, @"The notifiers should match.");
    XCTAssertEqualObjects(lastMessage.oldValue, @"test01", @"There should be an old value");
    XCTAssertEqualObjects(lastMessage.newValue, @"test02", @"There should be a new value");
}

- (void)testInitialSubscription {
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger timesInvoked = 0;
    __block ZCRMessage *lastMessage = nil;
    
    notifier.name = @"test01";
    
    BOOL result = [mailbox subscribeTo:notifier keyPath:@"name" options:options block:^(ZCRMessage *message) {
        timesInvoked++;
        lastMessage = message;
    }];
    
    XCTAssertTrue(result, @"The subscription should be added");
    
    XCTAssertTrue(timesInvoked == 1, @"The block should be invoked once.");
    XCTAssertEqualObjects(lastMessage.notifier, notifier, @"The notifiers should match.");
    XCTAssertEqualObjects(lastMessage.newValue, @"test01", @"There should be an initial value");
    
    notifier.name = @"test02";
    
    XCTAssertTrue(timesInvoked == 2, @"The block should be invoked twice.");
    XCTAssertEqualObjects(lastMessage.notifier, notifier, @"The notifiers should match.");
    XCTAssertEqualObjects(lastMessage.oldValue, @"test01", @"There should be an old value");
    XCTAssertEqualObjects(lastMessage.newValue, @"test02", @"There should be a new value");
}

- (void)testPriorSubscription {
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger timesInvoked = 0;
    __block ZCRMessage *priorMessage;
    __block ZCRMessage *afterMessage;
    
    notifier.name = @"test01";
    
    BOOL result = [mailbox subscribeTo:notifier keyPath:@"name" options:options block:^(ZCRMessage *message) {
        timesInvoked++;
        
        if (!priorMessage) { priorMessage = message; }
        else { afterMessage = message; }
    }];
    
    XCTAssertTrue(result, @"The subscription should be added");
    
    notifier.name = @"test02";
    
    XCTAssertTrue(timesInvoked == 2, @"The block should be invoked twice");
    
    XCTAssertTrue(priorMessage.isPriorToChange, @"The prior message should be flagged as such.");
    XCTAssertEqualObjects(priorMessage.notifier, notifier, @"The notifiers should match on the prior message.");
    XCTAssertEqualObjects(priorMessage.oldValue, @"test01", @"The old value should be set on the prior message.");
    XCTAssertNil(priorMessage.newValue, @"The new value should be nil on the prior message.");
    
    XCTAssertFalse(afterMessage.isPriorToChange, @"The after message should be flagged as such.");
    XCTAssertEqualObjects(afterMessage.notifier, notifier, @"The notifiers should match on the after message.");
    XCTAssertEqualObjects(afterMessage.oldValue, @"test01", @"The old value should be set on the after message.");
    XCTAssertEqualObjects(afterMessage.newValue, @"test02", @"The new value should be set on the after message.");
}

- (void)testMultipleKeyPathSubscriptions {
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger nameInvoked = 0;
    __block ZCRMessage *nameMessage = nil;
    
    BOOL result01 = [mailbox subscribeTo:notifier keyPath:@"name" options:options block:^(ZCRMessage *message) {
        nameInvoked++;
        nameMessage = message;
    }];
    
    XCTAssertTrue(result01, @"The subscription should be added");
    
    __block NSUInteger identifierInvoked = 0;
    __block ZCRMessage *identifierMessage = nil;
    
    BOOL result02 = [mailbox subscribeTo:notifier keyPath:@"identifier" options:options block:^(ZCRMessage *message) {
        identifierInvoked++;
        identifierMessage = message;
    }];
    
    XCTAssertTrue(result02, @"The subscription should be added");
    
    notifier.name = @"test01";
    
    XCTAssertTrue(nameInvoked == 1, @"The name-block should be invoked once.");
    XCTAssertEqualObjects(nameMessage.notifier, notifier, @"The name-notifiers should match.");
    XCTAssertEqualObjects(nameMessage.newValue, @"test01", @"There should be a new name");
    
    XCTAssertTrue(identifierInvoked == 0, @"The identifier-block should not be invoked.");
    XCTAssertNil(identifierMessage, @"The identifier-message should still be nil.");
    
    notifier.identifier = 1;
    
    XCTAssertTrue(identifierInvoked == 1, @"The identifier-block should be invoked once.");
    XCTAssertEqualObjects(identifierMessage.notifier, notifier, @"The identifier-notifiers should match.");
    XCTAssertEqualObjects(identifierMessage.newValue, @(1), @"There should be a new identifier");
    
    XCTAssertTrue(nameInvoked == 1, @"The name-block should still be invoked once.");
}

- (void)testMultipleNotifierSubscriptions {
    ZCRModel *notifier01 = [ZCRModel new];
    ZCRModel *notifier02 = [ZCRModel new];
    
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger notifier01Invoked = 0;
    __block ZCRMessage *notifier01Message = nil;
    
    BOOL result01 = [mailbox subscribeTo:notifier01 keyPath:@"name" options:options block:^(ZCRMessage *message) {
        notifier01Invoked++;
        notifier01Message = message;
    }];
    
    XCTAssertTrue(result01, @"The subscription should be added");
    
    __block NSUInteger notifier02Invoked = 0;
    __block ZCRMessage *notifier02Message = nil;
    
    BOOL result02 = [mailbox subscribeTo:notifier02 keyPath:@"name" options:options block:^(ZCRMessage *message) {
        notifier02Invoked++;
        notifier02Message = message;
    }];
    
    XCTAssertTrue(result02, @"The subscription should be added");
    
    notifier01.name = @"test01";
    notifier02.name = @"test02";
    
    XCTAssertTrue(notifier01Invoked == 1, @"The first block should be invoked once");
    XCTAssertEqualObjects(notifier01Message.notifier, notifier01, @"The first notifiers should match");
    XCTAssertEqualObjects(notifier01Message.newValue, @"test01", @"There should be a new name for the first notifier");
    
    XCTAssertTrue(notifier02Invoked == 1, @"The second block should be invoked once");
    XCTAssertEqualObjects(notifier02Message.notifier, notifier02, @"The second notifiers should match");
    XCTAssertEqualObjects(notifier02Message.newValue, @"test02", @"There should be a new name for the second notifier");
    
    notifier02.name = @"test03";
    
    XCTAssertTrue(notifier01Invoked == 1, @"The first block should still be invoked once");
    
    XCTAssertTrue(notifier02Invoked == 2, @"The second block should be invoked twice");
    XCTAssertEqualObjects(notifier02Message.notifier, notifier02, @"The second notifiers should match");
    XCTAssertEqualObjects(notifier02Message.oldValue, @"test02", @"There should be an old name for the second notifier");
    XCTAssertEqualObjects(notifier02Message.newValue, @"test03", @"There should be a new name for the second notifier");
}

- (void)testSubscribeWithoutNotifier {
    BOOL result = [mailbox subscribeTo:nil keyPath:@"name" options:NSKeyValueObservingOptionNew block:^(ZCRMessage *message) {}];
    XCTAssertFalse(result, @"The subscription should not be added");
}

- (void)testSubscribeWithoutKeyPath {
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger timesInvoked = 0;
    __block ZCRMessage *lastMessage = nil;
    
    BOOL result = [mailbox subscribeTo:notifier keyPath:nil options:options block:^(ZCRMessage *message) {
        timesInvoked++;
        lastMessage = message;
    }];
    
    XCTAssertFalse(result, @"The subscription should not be added");
    
    notifier.name = @"test01";
    notifier.identifier = 1;
    
    XCTAssertTrue(timesInvoked == 0, @"The block should not be invoked");
    XCTAssertNil(lastMessage, @"No message should be sent.");
}

- (void)testSubscribeWithoutBlock {
    BOOL result = [mailbox subscribeTo:notifier keyPath:@"name" options:NSKeyValueObservingOptionNew block:nil];
    XCTAssertFalse(result, @"The subscription should not be added");
}

- (void)testSubscribeWithRegisteredKeyPath {
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger timesInvoked01 = 0;
    __block ZCRMessage *lastMessage01 = nil;
    
    BOOL result01 = [mailbox subscribeTo:notifier keyPath:@"name" options:options block:^(ZCRMessage *message) {
        timesInvoked01++;
        lastMessage01 = message;
    }];
    
    XCTAssertTrue(result01, @"The subscription should be added");
    
    __block NSUInteger timesInvoked02 = 0;
    __block ZCRMessage *lastMessage02 = nil;
    
    BOOL result02 = [mailbox subscribeTo:notifier keyPath:@"name" options:options block:^(ZCRMessage *message) {
        timesInvoked02++;
        lastMessage02 = message;
    }];
    
    XCTAssertFalse(result02, @"The subscription should not be added");
    
    notifier.name = @"test01";
    
    XCTAssertTrue(timesInvoked01 == 1, @"The first block should be invoked once.");
    XCTAssertNotNil(lastMessage01, @"The first message should be sent.");
    
    XCTAssertTrue(timesInvoked02 == 0, @"The second block should not be invoked");
    XCTAssertNil(lastMessage02, @"No second message should be sent.");
}

- (void)testUnsubscribeKeyPath {
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger timesInvoked = 0;
    __block ZCRMessage *lastMessage = nil;
    
    [mailbox subscribeTo:notifier keyPath:@"name" options:options block:^(ZCRMessage *message) {
        timesInvoked++;
        lastMessage = message;
    }];
    
    notifier.name = @"test01";
    
    XCTAssertTrue(timesInvoked == 1, @"The block should be invoked once.");
    XCTAssertNotNil(lastMessage, @"The last message should be set.");
    
    lastMessage = nil;
    
    XCTAssertTrue([mailbox unsubscribeFrom:notifier keyPath:@"name"], @"The subscription should be removed.");
    
    notifier.name = @"test02";
    
    XCTAssertTrue(timesInvoked == 1, @"The block should still be invoked once.");
    XCTAssertNil(lastMessage, @"The last message should not be set.");
}

- (void)testUnsubscribeNotifier {
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger nameInvoked = 0;
    __block ZCRMessage *nameMessage = nil;
    
    [mailbox subscribeTo:notifier keyPath:@"name" options:options block:^(ZCRMessage *message) {
        nameInvoked++;
        nameMessage = message;
    }];
    
    __block NSUInteger identifierInvoked = 0;
    __block ZCRMessage *identifierMessage = nil;
    
    [mailbox subscribeTo:notifier keyPath:@"identifier" options:options block:^(ZCRMessage *message) {
        identifierInvoked++;
        identifierMessage = message;
    }];
    
    notifier.name = @"test01";
    notifier.identifier = 1;
    
    XCTAssertTrue(nameInvoked == 1, @"The name block should be invoked once.");
    XCTAssertNotNil(nameMessage, @"The name message should be set.");
    
    nameMessage = nil;
    
    XCTAssertTrue(identifierInvoked == 1, @"The identifier block should be invoked once.");
    XCTAssertNotNil(identifierMessage, @"The identifier message should be set.");
    
    identifierMessage = nil;
    
    XCTAssertTrue([mailbox unsubscribeFrom:notifier], @"The subscriptions should be removed.");
    
    notifier.name = @"test02";
    notifier.identifier = 2;
    
    XCTAssertTrue(nameInvoked == 1, @"The name block should still be invoked once.");
    XCTAssertNil(nameMessage, @"The name message should be unset.");
    
    XCTAssertTrue(identifierInvoked == 1, @"The identifier block should still be invoked once.");
    XCTAssertNil(identifierMessage, @"The identifier message should be unset.");
}

- (void)testUnsubscribeAll {
    ZCRModel *notifier01 = [ZCRModel new];
    ZCRModel *notifier02 = [ZCRModel new];
    
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger notifier01Invoked = 0;
    __block ZCRMessage *notifier01Message = nil;
    
    [mailbox subscribeTo:notifier01 keyPath:@"name" options:options block:^(ZCRMessage *message) {
        notifier01Invoked++;
        notifier01Message = message;
    }];
    
    __block NSUInteger notifier02Invoked = 0;
    __block ZCRMessage *notifier02Message = nil;
    
    [mailbox subscribeTo:notifier02 keyPath:@"name" options:options block:^(ZCRMessage *message) {
        notifier02Invoked++;
        notifier02Message = message;
    }];
    
    notifier01.name = @"test01";
    notifier02.name = @"test02";
    
    XCTAssertTrue(notifier01Invoked == 1, @"The first block should be invoked once.");
    XCTAssertNotNil(notifier01Message, @"The first message should be set.");
    
    notifier01Message = nil;
    
    XCTAssertTrue(notifier02Invoked == 1, @"The second block should be invoked once.");
    XCTAssertNotNil(notifier02Message, @"The second message should be set.");
    
    notifier02Message = nil;
    
    [mailbox unsubscribeFromAll];
    
    notifier01.name = @"test03";
    notifier02.name = @"test04";
    
    XCTAssertTrue(notifier01Invoked == 1, @"The first block should still be invoked once.");
    XCTAssertNil(notifier01Message, @"The first message should be unset.");
    
    XCTAssertTrue(notifier02Invoked == 1, @"The second block should still be invoked once.");
    XCTAssertNil(notifier02Message, @"The second message should be unset.");
}

- (void)testSubscribeUnsubscribeAllKeyPathsFreesNotifier {
    __weak ZCRModel *model = nil;
    
    @autoreleasepool {
        ZCRModel *strongModel = [[ZCRModel alloc] init];
        model = strongModel;
        
        [mailbox subscribeTo:model keyPath:@"name" options:0 block:^(ZCRMessage *message) {
        }];
    }
    
    XCTAssertNotNil(model, @"The model should be retained as long as the subscription lasts");
    
    @autoreleasepool {
        [mailbox unsubscribeFrom:model keyPath:@"name"];
    }
    
    XCTAssertNil(model, @"Once all subscriptions are removed, the model should be released");
}

- (void)testSubscribeUnsubscribeNotifierFreesNotifier {
    __weak ZCRModel *model = nil;
    
    @autoreleasepool {
        ZCRModel *strongModel = [[ZCRModel alloc] init];
        model = strongModel;
        
        [mailbox subscribeTo:model keyPath:@"name" options:0 block:^(ZCRMessage *message) {
        }];
    }
    
    XCTAssertNotNil(model, @"The model should be retained as long as the subscription lasts");
    
    @autoreleasepool {
        [mailbox unsubscribeFrom:model];
    }
    
    XCTAssertNil(model, @"Once all subscriptions are removed, the model should be released");
}

- (void)testSubscribeUnsubscribeAllFreesNotifier {
    __weak ZCRModel *model = nil;
    
    @autoreleasepool {
        ZCRModel *strongModel = [[ZCRModel alloc] init];
        model = strongModel;
        
        [mailbox subscribeTo:model keyPath:@"name" options:0 block:^(ZCRMessage *message) {
        }];
    }
    
    XCTAssertNotNil(model, @"The model should be retained as long as the subscription lasts");
    
    @autoreleasepool {
        [mailbox unsubscribeFromAll];
    }
    
    XCTAssertNil(model, @"Once all subscriptions are removed, the model should be released");
}

- (void)testUnsubscribeWithoutKeyPath {
    __block NSUInteger timesInvoked = 0;
    
    BOOL result01 = [mailbox subscribeTo:notifier keyPath:@"name" options:NSKeyValueObservingOptionNew block:^(ZCRMessage *message) {
        timesInvoked++;
    }];
    
    XCTAssertTrue(result01, @"The subscription should be added.");
    
    BOOL result02 = [mailbox unsubscribeFrom:notifier keyPath:nil];
    
    XCTAssertFalse(result02, @"The subscription should not be removed.");
    
    notifier.name = @"test01";
    
    XCTAssertTrue(timesInvoked == 1, @"The block should be invoked once.");
}

- (void)testUnsubscribeWithoutNotifier {
    BOOL result = [mailbox unsubscribeFrom:nil];
    XCTAssertFalse(result, @"The subscription should not be removed");
}

- (void)testUnsubscribeUnknownNotifier {
    __block NSUInteger timesInvoked = 0;
    
    BOOL result01 = [mailbox subscribeTo:notifier keyPath:@"name" options:NSKeyValueObservingOptionNew block:^(ZCRMessage *message) {
        timesInvoked++;
    }];
    
    XCTAssertTrue(result01, @"The subscription should be added");
    
    ZCRModel *unknownNotifier = [ZCRModel new];
    
    BOOL result02 = [mailbox unsubscribeFrom:unknownNotifier];
    
    XCTAssertFalse(result02, @"The subscription should not be removed.");
    
    notifier.name = @"test01";
    
    XCTAssertTrue(timesInvoked == 1, @"The block should be invoked once");
}

- (void)testDealloc {
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
    
    __block NSUInteger timesInvoked = 0;
    __block ZCRMessage *lastMessage = nil;
    
    @autoreleasepool {
        ZCRMailbox *tempMailbox = [[ZCRMailbox alloc] initWithSubscriber:subscriber];
        
        [tempMailbox subscribeTo:notifier keyPath:@"name" options:options block:^(ZCRMessage *message) {
            timesInvoked++;
            lastMessage = message;
        }];
        
        notifier.name = @"test01";
        
        XCTAssertTrue(timesInvoked == 1, @"The block should be invoked once.");
        XCTAssertNotNil(lastMessage, @"The last message should not be nil.");
        
        lastMessage = nil;
    }
    
    notifier.name = @"test02";
    
    XCTAssertTrue(timesInvoked == 1, @"The block should still be invoked once.");
    XCTAssertNil(lastMessage, @"The last message should be unset.");
}

- (void)testMultipleThreads {
    BOOL shouldRun = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (shouldRun) {
            XCTAssertNoThrow(^{
                notifier.time = [NSDate timeIntervalSinceReferenceDate];
            }(), @"The KVO notification should succeed.");
        }
    });
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (shouldRun) {
            @autoreleasepool {
                ZCRMailbox *tempMailbox = [[ZCRMailbox alloc] initWithSubscriber:subscriber];
                [tempMailbox subscribeTo:notifier keyPath:@"identifier" options:0 block:^(ZCRMessage *message) {
                }];
            }
        }
    });
    
    NSDate *waitUntil = [NSDate dateWithTimeIntervalSinceNow:5.0];
    
    while ([waitUntil timeIntervalSinceNow] > 0.0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    
    shouldRun = NO;
}

@end
