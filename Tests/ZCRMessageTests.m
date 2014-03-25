//
//  ZCRMessageTests.m
//  ZCRMailbox
//
//  Created by Zachary Radke on 3/25/14.
//  Copyright (c) 2014 Zach Radke. All rights reserved.
//

#import "ZCRMailbox.h"

#import <XCTest/XCTest.h>

@interface ZCRMessageTests : XCTestCase {
    id notifier;
    NSString *keyPath;
    NSDictionary *change;
    ZCRMessage *message;
}
@end

@implementation ZCRMessageTests

- (void)setUp {
    [super setUp];
    
    notifier = [NSObject new];
    keyPath = @"names";
    change = @{NSKeyValueChangeKindKey: @(NSKeyValueChangeReplacement),
               NSKeyValueChangeNewKey: @"test02", // A prior change will never have the new key, but we use it here for testing
               NSKeyValueChangeOldKey: @"test01",
               NSKeyValueChangeIndexesKey: [NSIndexSet indexSetWithIndex:0],
               NSKeyValueChangeNotificationIsPriorKey: @(YES)};
    
    message = [[ZCRMessage alloc] initWithNotifier:notifier keyPath:keyPath change:change];
}

- (void)tearDown {
    message = nil;
    
    change = nil;
    keyPath = nil;
    notifier = nil;
    
    [super tearDown];
}

- (void)testNotifier {
    XCTAssertEqualObjects(message.notifier, notifier, @"The notifiers should match.");
}

- (void)testKeyPath {
    XCTAssertEqualObjects(message.keyPath, keyPath, @"The key paths should match.");
}

- (void)testKind {
    XCTAssertEqual(message.kind, NSKeyValueChangeReplacement, @"The change kind should match.");
}

- (void)testNewValue {
    XCTAssertEqualObjects(message.newValue, @"test02", @"The new value should be set.");
}

- (void)testOldValue {
    XCTAssertEqualObjects(message.oldValue, @"test01", @"The old value should be set.");
}

- (void)testIndexes {
    XCTAssertEqualObjects(message.indexes, [NSIndexSet indexSetWithIndex:0], @"There should be indexes set.");
}

- (void)testIsPriorToChange {
    XCTAssertTrue(message.isPriorToChange, @"The message should be prior to the change.");
}

- (void)testNullNewValue {
    NSMutableDictionary *mutableChange = [change mutableCopy];
    mutableChange[NSKeyValueChangeNewKey] = [NSNull null];
    
    message = [[ZCRMessage alloc] initWithNotifier:notifier keyPath:keyPath change:mutableChange];
    
    XCTAssertNil(message.newValue, @"The null value should be converted to nil.");
}

- (void)testNullOldValue {
    NSMutableDictionary *mutableChange = [change mutableCopy];
    mutableChange[NSKeyValueChangeOldKey] = [NSNull null];
    
    message = [[ZCRMessage alloc] initWithNotifier:notifier keyPath:keyPath change:mutableChange];
    
    XCTAssertNil(message.oldValue, @"The null value should be converted to nil.");
}

@end
