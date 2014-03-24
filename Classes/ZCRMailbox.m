//
//  ZCRMailbox.m
//  ZCRMailbox
//
//  Created by Zachary Radke on 3/20/14.
//  Copyright (c) 2014 Zach Radke. All rights reserved.
//

#import "ZCRMailbox.h"

/**
 *  Private object representing a single subscription to a notifier made by a ZCRMailbox.
 */
@interface _ZCRSubscription : NSObject

@property (weak, nonatomic, readonly) ZCRMailbox *mailbox;
@property (weak, nonatomic, readonly) id notifier;
@property (strong, nonatomic, readonly) NSString *keyPath;
@property (assign, nonatomic, readonly) NSKeyValueObservingOptions options;
@property (strong, nonatomic, readonly) void (^block)(ZCRMessage *message);

- (instancetype)initWithMailbox:(ZCRMailbox *)mailbox notifier:(id)notifier keyPath:(NSString *)keyPath
                        options:(NSKeyValueObservingOptions)options
                          block:(void (^)(ZCRMessage *))block;

@end


/**
 *  Private coordinator which receives all subscription and unsubscription requests. This object also is the true receiver for all KVO
 *  notifications subscribed to through ZCRMailbox instances.
 *
 *  Because KVO subscriptions and unsubscriptions are expected to be made synchronously, a simple NSRecursiveLock is used to ensure thread
 *  safety between all the subscription and unsubscription requests. This has the adverse effect of creating a bottleneck if a large number
 *  of subscription and unsubscription requests are made within a short space of time, but should serve for present.
 *
 *  The _ZCRSubscriptions are strongly retained in an NSMutableSet, since all unsubscriptions are made simultaneously to removing them from
 *  the ZCRMailbox.
 */
@interface _ZCRPostOffice : NSObject

@property (strong, nonatomic) NSRecursiveLock *lock;
@property (strong, nonatomic, readonly) NSMutableSet *subscriptions;

+ (instancetype)sharedPostOffice;

- (void)addSubscription:(_ZCRSubscription *)subscription forNotifier:(id)notifier;

- (void)removeSubscriptions:(NSSet *)subscriptions forNotifier:(id)notifier;

@end


/**
 *  Additional properties for the ZCRMailbox. Thread-safety is guaranteed by a simple NSRecursiveLock, since a single mailbox is highly
 *  unlikely to encounter a massive number of subscription and unsubscription requests.
 */
@interface ZCRMailbox ()
@property (strong, nonatomic, readonly) NSRecursiveLock *lock;
@property (strong, nonatomic, readonly) NSMutableDictionary *subscriptionsForNotifiers;
@end

@implementation ZCRMailbox

- (instancetype)initWithSubscriber:(id)subscriber {
    if (!(self = [super init])) { return nil; }
    
    _subscriber = subscriber;
    
    _lock = [[NSRecursiveLock alloc] init];
    _lock.name = [NSString stringWithFormat:@"com.zachradke.mailbox.%p.lock", self];
    
    _subscriptionsForNotifiers = [NSMutableDictionary dictionary];
    
    return self;
}

- (instancetype)init {
    return [self initWithSubscriber:nil];
}

- (void)dealloc {
    // Deallocation will naturally remove all subscriptions
    [self unsubscribeFromAll];
}

- (BOOL)subscribeTo:(id)notifier keyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options
              block:(void (^)(ZCRMessage *))block {
    if (!notifier || !keyPath || !block) { return NO; }
    
    _ZCRSubscription *subscription = [[_ZCRSubscription alloc] initWithMailbox:self notifier:notifier keyPath:keyPath
                                                                       options:options
                                                                         block:block];
    
    return [self _addSubscription:subscription forNotifier:notifier];
}

- (void)unsubscribeFromAll {
    [self.lock lock];
    
    [self _enumerateNotifiersAndSubscriptionsUsingBlock:^(id notifier, NSMutableSet *subscriptions, BOOL *stop) {
        [[_ZCRPostOffice sharedPostOffice] removeSubscriptions:subscriptions forNotifier:notifier];
    }];
    
    [self.subscriptionsForNotifiers removeAllObjects];
    
    [self.lock unlock];
}

- (BOOL)_addSubscription:(_ZCRSubscription *)subscription forNotifier:(id)notifier {
    if (!subscription || !notifier) { return NO; }
    
    [self.lock lock];
    
    __block NSMutableSet *subscriptions = nil;
    
    [self _enumerateNotifiersAndSubscriptionsUsingBlock:^(id existingNotifier, NSMutableSet *existingSubscriptions, BOOL *stop) {
        // We are using pointer equality to check for a match rather than isEqual: to ensure we have the *exact* object which was registered.
        if (existingNotifier == notifier) {
            subscriptions = existingSubscriptions;
            *stop = YES;
        }
    }];
    
    if (!subscriptions) {
        subscriptions = [NSMutableSet set];
        
        // As a tricksy way of getting around the NSCopying requirement for dictionary keys, we wrap the notifier in a block to use as a key.
        id key = ^id { return notifier; };
        
        self.subscriptionsForNotifiers[key] = subscriptions;
    }
    
    // We ensure that a single notifier-keyPath pair is registered per mailbox.
    NSPredicate *keyPathPredicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(keyPath)), subscription.keyPath];
    
    NSSet *matchingSubscriptions = [subscriptions filteredSetUsingPredicate:keyPathPredicate];
    
    if (matchingSubscriptions.count == 0) {
        [subscriptions addObject:subscription];
        
        [[_ZCRPostOffice sharedPostOffice] addSubscription:subscription forNotifier:notifier];
    }
    
    [self.lock unlock];
    
    return (matchingSubscriptions.count == 0);
}

- (BOOL)unsubscribeFrom:(id)notifier {
    if (!notifier) { return NO; }
    
    NSMutableDictionary *subscriptionsForNotifiers = self.subscriptionsForNotifiers;
    
    [self.lock lock];
    
    __block id foundKey = nil;
    
    // Because we need to get the actual dictionary key object, we can't use the enumerateNotifiersAndSubscriptionsUsingBlock: method
    [subscriptionsForNotifiers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        id (^notifierBlock)() = key;
        id existingNotifier = notifierBlock();
        
        if (existingNotifier == notifier) {
            foundKey = key;
            [[_ZCRPostOffice sharedPostOffice] removeSubscriptions:obj forNotifier:notifier];
            *stop = YES;
        }
    }];
    
    if (foundKey) {
        [subscriptionsForNotifiers removeObjectForKey:foundKey];
    }
    
    [self.lock unlock];
    
    return (foundKey != nil);
}

- (BOOL)unsubscribeFrom:(id)notifier keyPath:(NSString *)keyPath {
    if (!notifier || !keyPath) { return NO; }
    
    [self.lock lock];
    
    __block NSMutableSet *subscriptions = nil;
    
    [self _enumerateNotifiersAndSubscriptionsUsingBlock:^(id existingNotifier, NSMutableSet *existingSubscriptions, BOOL *stop) {
        if (existingNotifier == notifier) {
            subscriptions = existingSubscriptions;
            *stop = YES;
        }
    }];
    
    if (!subscriptions) {
        [self.lock unlock];
        return NO;
    }
    
    NSPredicate *keyPathPredicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(keyPath)), keyPath];
    
    NSSet *matchingSubscriptions = [subscriptions filteredSetUsingPredicate:keyPathPredicate];
    
    if (matchingSubscriptions.count > 0) {
        [[_ZCRPostOffice sharedPostOffice] removeSubscriptions:matchingSubscriptions forNotifier:notifier];
        [subscriptions minusSet:matchingSubscriptions];
    }
    
    [self.lock unlock];
    
    return (matchingSubscriptions.count > 0);
}

- (void)_enumerateNotifiersAndSubscriptionsUsingBlock:(void (^)(id notifier, NSMutableSet *subscriptions, BOOL *stop))block {
    if (!block) { return; }
    
    [self.subscriptionsForNotifiers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        // Because of our tricksy way of storing the notifiers, we need to unpack the key to get the actual notifier
        id (^notifierBlock)() = key;
        id notifier = notifierBlock();
        
        block(notifier, obj, stop);
    }];
}

@end


@implementation _ZCRPostOffice

+ (instancetype)sharedPostOffice {
    static _ZCRPostOffice *sharedPostOffice;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPostOffice = [[self alloc] init];
    });
    
    return sharedPostOffice;
}

- (instancetype)init {
    if (!(self = [super init])) { return nil; }
    
    _lock = [[NSRecursiveLock alloc] init];
    _lock.name = [NSString stringWithFormat:@"com.zachradke.mailbox.postOffice.%p.lock", self];
    
    _subscriptions = [NSMutableSet set];
    
    return self;
}

- (void)addSubscription:(_ZCRSubscription *)subscription forNotifier:(id)notifier {
    if (!subscription || !notifier) { return; }
    
    NSMutableSet *subscriptions = self.subscriptions;
    
    [self.lock lock];
    
    // This is highly unlikely since equality is pretty strict, but better safe than sorry!
    if ([subscriptions containsObject:subscription]) {
        [self.lock unlock];
        return;
    }
    
    [subscriptions addObject:subscription];
    
    // For now these conditionals only apply to NSArrays, but in the future these more efficient observation methods for colletions might
    // be added, so we try and future proof here.
    if ([notifier respondsToSelector:@selector(addObserver:toObjectsAtIndexes:forKeyPath:options:context:)] &&
        [notifier respondsToSelector:@selector(removeObserver:fromObjectsAtIndexes:forKeyPath:context:)] &&
        [notifier respondsToSelector:@selector(count)]) {
        NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [notifier count])];
        [notifier addObserver:self toObjectsAtIndexes:indexes
                   forKeyPath:subscription.keyPath
                      options:subscription.options
                      context:(__bridge void *)subscription];
    } else {
        [notifier addObserver:self forKeyPath:subscription.keyPath options:subscription.options context:(__bridge void *)subscription];
    }
    
    [self.lock unlock];
}

- (void)removeSubscriptions:(NSSet *)subscriptions forNotifier:(id)notifier {
    if (subscriptions.count == 0 || !notifier) { return; }
    
    [self.lock lock];
    
    [self.subscriptions minusSet:subscriptions];
    
    for (_ZCRSubscription *subscription in subscriptions) {
        // For now these conditionals only apply to NSArrays, but in the future these more efficient observation methods for colletions might
        // be added, so we try and future proof here.
        if ([notifier respondsToSelector:@selector(addObserver:toObjectsAtIndexes:forKeyPath:options:context:)] &&
            [notifier respondsToSelector:@selector(removeObserver:fromObjectsAtIndexes:forKeyPath:context:)] &&
            [notifier respondsToSelector:@selector(count)]) {
            NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [notifier count])];
            [notifier removeObserver:self fromObjectsAtIndexes:indexes forKeyPath:subscription.keyPath context:(void *)subscription];
        } else {
            [notifier removeObserver:self forKeyPath:subscription.keyPath context:(void *)subscription];
        }
    }
    
    [self.lock unlock];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [self.lock lock];
    
    _ZCRSubscription *subscription = [self.subscriptions member:(__bridge id)context];
    
    [self.lock unlock];
    
    // This should never happen, but just in case we somehow have a dangling KVO subscription...
    if (!subscription) {
        // We need to wrap this in a @try... @catch block because there are no guarantees how this was added, or if it is safe to remove
        @try {
            if ([object respondsToSelector:@selector(addObserver:toObjectsAtIndexes:forKeyPath:options:context:)] &&
                [object respondsToSelector:@selector(removeObserver:fromObjectsAtIndexes:forKeyPath:context:)] &&
                [object respondsToSelector:@selector(count)]) {
                NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [object count])];
                [object removeObserver:self fromObjectsAtIndexes:indexes forKeyPath:keyPath context:context];
            } else {
                [object removeObserver:self forKeyPath:keyPath context:context];
            }
        }
        @catch (NSException *__unused exception) {}
        
        return;
    }
    
    // We need to grab hold of this weak subscriber
    id subscriber = subscription.mailbox.subscriber;
    
    ZCRMessage *message = [[ZCRMessage alloc] initWithNotifier:object keyPath:keyPath change:change];
    
    // If we can't notify the subscriber for whatever reason, we should remove this subscription
    if (![self _notifySubscriber:subscriber withMessage:message subscription:subscription]) {
        [self removeSubscriptions:[NSSet setWithObject:subscription] forNotifier:object];
    }
}

- (BOOL)_notifySubscriber:(id)subscriber withMessage:(ZCRMessage *)message subscription:(_ZCRSubscription *)subscription {
    if (!subscriber || !message || !subscription) { return NO; }
    
    if (subscription.block) {
        subscription.block(message);
        
        return YES;
    }
    
    // In the future we can add more notification methods... selectors... KVO fallbacks...
    
    return NO;
}

@end


@implementation _ZCRSubscription

- (instancetype)initWithMailbox:(ZCRMailbox *)mailbox notifier:(id)notifier keyPath:(NSString *)keyPath
                        options:(NSKeyValueObservingOptions)options
                          block:(void (^)(ZCRMessage *))block {
    if (!(self = [super init])) { return nil; }
    
    _mailbox = mailbox;
    _notifier = notifier;
    _keyPath = [keyPath copy];
    _options = options;
    _block = [block copy];
    
    return self;
}

- (instancetype)init {
    return [self initWithMailbox:nil notifier:nil keyPath:nil options:0 block:nil];
}

- (NSUInteger)hash {
    // For hashing we use the mailbox, notifier, keypath, and options, but exclude the block.
    // Although the mailbox and notifier are weak, we can safely use them here because the ZCRMailbox will strongly retain both this and
    // the notifier, so they should never become nil before this instance deallocates.
    return [_mailbox hash] ^ [_notifier hash] ^ [_keyPath hash] ^ _options;
}

- (BOOL)isEqual:(id)object {
    if (object == self) { return YES; }
    if (![object isKindOfClass:[self class]]) { return NO; }
    
    _ZCRSubscription *other = object;
    
    ZCRMailbox *mailbox = self.mailbox;
    ZCRMailbox *otherMailbox = other.mailbox;
    
    // We require the pointers be equal for the mailboxes to be considered the same, incase we later foolishly make an isEqual: method on
    // ZCRMailbox that doesn't guarantee uniqueness.
    BOOL equalMailboxes = (!mailbox && !otherMailbox) || (mailbox == otherMailbox);
    
    id notifier = self.notifier;
    id otherNotifier = other.notifier;
    
    // Like the mailbox check, we use pointer equality for notifiers since we cannot guarantee that a sufficiently strict isEqual: method
    // exists on the notifiers.
    BOOL equalNotifiers = (!notifier && !otherNotifier) || (notifier == otherNotifier);
    
    BOOL equalKeyPaths = (!self.keyPath && !other.keyPath) || [self.keyPath isEqualToString:other.keyPath];
    BOOL equalOptions = self.options == other.options;
    
    return equalMailboxes && equalNotifiers && equalKeyPaths && equalOptions;
}

@end


@implementation ZCRMessage

- (instancetype)initWithNotifier:(id)notifier keyPath:(NSString *)keyPath change:(NSDictionary *)change {
    if (!(self = [super init])) { return nil; }
    
    // These properties should always be present regardless of the NSKeyValueObservingOptions
    _notifier = notifier;
    _keyPath = [keyPath copy];
    _kind = [change[NSKeyValueChangeKindKey] unsignedIntegerValue];
    
    
    // These properties depend on the NSKeyValueObservingOptions passed when registering for KVO. As such, sometimes they return NSNulls
    // to report nil values. We convert these to nil.
    _oldValue = change[NSKeyValueChangeOldKey];
    
    if (_oldValue == (id)[NSNull null]) { _oldValue = nil; }
    
    _newValue = change[NSKeyValueChangeNewKey];
    
    if (_newValue == (id)[NSNull null]) { _newValue = nil; }
    
    _indexes = change[NSKeyValueChangeIndexesKey];
    
    if (_indexes == (id)[NSNull null]) { _indexes = nil; }
    
    _isPriorToChange = [change[NSKeyValueChangeNotificationIsPriorKey] boolValue];
    
    return self;
}

- (instancetype)init {
    return [self initWithNotifier:nil keyPath:nil change:nil];
}

@end


