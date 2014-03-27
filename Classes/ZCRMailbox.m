//
//  ZCRMailbox.m
//  ZCRMailbox
//
//  Created by Zachary Radke on 3/20/14.
//  Copyright (c) 2014 Zach Radke. All rights reserved.
//

#import "ZCRMailbox.h"

NSString *ZCRStringForKVOOptions(NSKeyValueObservingOptions options) {
    NSMutableArray *optionStrings = [NSMutableArray array];
    
    if (options & NSKeyValueObservingOptionInitial) {
        [optionStrings addObject:@"NSKeyValueObservingOptionInitial"];
    }
    
    if (options & NSKeyValueObservingOptionNew) {
        [optionStrings addObject:@"NSKeyValueObservingOptionNew"];
    }
    
    if (options & NSKeyValueObservingOptionOld) {
        [optionStrings addObject:@"NSKeyValueObservingOptionOld"];
    }
    
    if (options & NSKeyValueObservingOptionPrior) {
        [optionStrings addObject:@"NSKeyValueObservingOptionPrior"];
    }
    
    return (optionStrings.count > 0) ? [optionStrings componentsJoinedByString:@"|"] : @"None";
}

NSString *ZCRStringForKVOKind(NSKeyValueChange kind) {
    switch (kind) {
        case NSKeyValueChangeSetting:
            return @"NSKeyValueChangeSetting";
        case NSKeyValueChangeInsertion:
            return @"NSKeyValueChangeInsertion";
        case NSKeyValueChangeRemoval:
            return @"NSKeyValueChangeRemoval";
        case NSKeyValueChangeReplacement:
            return @"NSKeyValueChangeReplacement";
        default:
            return nil;
    }
}


/*
 *  Private object representing a single subscription to a notifier made by a ZCRMailbox.
 */
@interface _ZCRSubscription : NSObject

@property (weak, nonatomic, readonly) ZCRMailbox *mailbox;

@property (weak, nonatomic, readonly) id notifier;
@property (strong, nonatomic, readonly) NSString *keyPath;
@property (assign, nonatomic, readonly) NSKeyValueObservingOptions options;

@property (strong, nonatomic, readonly) void (^block)(ZCRMessage *message);
@property (assign, nonatomic, readonly) SEL selector;
@property (assign, nonatomic, readonly) void *userContext;

- (instancetype)initWithMailbox:(ZCRMailbox *)mailbox notifier:(id)notifier keyPath:(NSString *)keyPath
                        options:(NSKeyValueObservingOptions)options
                          block:(void (^)(ZCRMessage *))block selector:(SEL)selector context:(void *)userContext;

@end


/*
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

+ (instancetype)sharedPostOffice __attribute__((const));

- (BOOL)addSubscription:(_ZCRSubscription *)subscription;

- (BOOL)removeSubscriptions:(NSSet *)subscriptions;

@end


/*
 *  Additional properties for the ZCRMailbox. Thread-safety is guaranteed by a simple NSRecursiveLock, since a single mailbox is
 *  unlikely to encounter a massive number of subscription and unsubscription requests.
 */
@interface ZCRMailbox ()
@property (strong, nonatomic, readonly) NSRecursiveLock *lock;

@property (strong, nonatomic) NSMutableArray *notifiers;
@property (strong, nonatomic) NSMutableSet *subscriptions;
@end

@implementation ZCRMailbox

- (instancetype)initWithSubscriber:(id)subscriber {
    if (!(self = [super init])) { return nil; }
    
    _subscriber = subscriber;
    
    _lock = [[NSRecursiveLock alloc] init];
    _lock.name = [NSString stringWithFormat:@"com.zachradke.mailbox.%p.lock", self];
    
    _notifiers = [NSMutableArray array];
    _subscriptions = [NSMutableSet set];
    
    return self;
}

- (instancetype)init {
    return [self initWithSubscriber:nil];
}

- (void)dealloc {
    // Deallocation will naturally remove all subscriptions
    [self unsubscribeFromAll];
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@:%p> ", NSStringFromClass([self class]), self];
    
    id subscriber = _subscriber;
    [description appendFormat:@"subscriber:<%@:%p> ", NSStringFromClass([subscriber class]), subscriber];
    
    [self.lock lock];
    
    NSSet *subscriptions = [self.subscriptions copy];
    
    [self.lock unlock];
    
    [description appendString:@"subscriptions:("];
    
    for (_ZCRSubscription *subscription in subscriptions) {
        [description appendFormat:@"\n\t%@", subscription];
    }
    
    if (subscriptions.count > 0) {
        [description appendString:@"\n)"];
    } else {
        [description appendString:@")"];
    }
    
    return [description copy];
}

- (BOOL)subscribeTo:(id)notifier keyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options
              block:(void (^)(ZCRMessage *))block {
    if (!notifier || !keyPath || !block) { return NO; }
    
    _ZCRSubscription *subscription = [[_ZCRSubscription alloc] initWithMailbox:self notifier:notifier keyPath:keyPath
                                                                       options:options
                                                                         block:block selector:NULL context:NULL];
    
    return [self _addSubscription:subscription forNotifier:notifier];
}

- (BOOL)subscribeTo:(id)notifier keyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options
           selector:(SEL)selector {
    if (!notifier || !keyPath || !selector) { return NO; }
    
    NSMethodSignature *methodSignature = [self.subscriber methodSignatureForSelector:selector];
    
    // We require that the subscriber respond to the passed selector, and that it has 2 or 3 arguments
    if (!methodSignature || methodSignature.numberOfArguments > 3) { return NO; }
    
    _ZCRSubscription *subscription = [[_ZCRSubscription alloc] initWithMailbox:self notifier:notifier keyPath:keyPath
                                                                       options:options
                                                                         block:nil selector:selector context:NULL];
    
    return [self _addSubscription:subscription forNotifier:notifier];
}

- (BOOL)subscribeTo:(id)notifier keyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options
            context:(void *)userContext {
    if (!notifier || !keyPath) { return NO; }
    
    _ZCRSubscription *subscription = [[_ZCRSubscription alloc] initWithMailbox:self notifier:notifier keyPath:keyPath
                                                                       options:options
                                                                         block:nil selector:NULL context:userContext];
    
    return [self _addSubscription:subscription forNotifier:notifier];
}

- (BOOL)_addSubscription:(_ZCRSubscription *)subscription forNotifier:(id)notifier {
    if (!subscription || !notifier) { return NO; }
    
    BOOL success = NO;
    
    [self.lock lock];
    
    BOOL isNewNotifier = [self.notifiers indexOfObjectIdenticalTo:notifier] == NSNotFound;
    
    // New notifiers need to be added to the array
    if (isNewNotifier) {
        success = [[_ZCRPostOffice sharedPostOffice] addSubscription:subscription];
        
        if (success) {
            [self.notifiers addObject:notifier];
            [self.subscriptions addObject:subscription];
        }
    } else {
        // We need a custom predicate that checks the key-path and notifier pointers.
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(_ZCRSubscription *existingSubscription, NSDictionary *__unused bindings) {
            return existingSubscription.notifier == notifier && [existingSubscription.keyPath isEqualToString:subscription.keyPath];
        }];
        
        BOOL shouldAddSubscription = [[self.subscriptions filteredSetUsingPredicate:predicate] count] == 0;
        
        if (shouldAddSubscription) {
            success = [[_ZCRPostOffice sharedPostOffice] addSubscription:subscription];
            
            if (success) {
                [self.subscriptions addObject:subscription];
            }
        } else {
            success = NO;
        }
    }
    
    [self.lock unlock];
    
    return success;
}

- (BOOL)unsubscribeFrom:(id)notifier keyPath:(NSString *)keyPath {
    if (!notifier || !keyPath) { return NO; }
    
    [self.lock lock];
    
    BOOL success = NO;
    
    NSUInteger notifierIndex = [self.notifiers indexOfObjectIdenticalTo:notifier];
    
    if (notifierIndex != NSNotFound) {
        // We need a custom predicate that checks the key-path and notifier pointers
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(_ZCRSubscription *existingSubscription, NSDictionary *__unused bindings) {
            return existingSubscription.notifier == notifier && [existingSubscription.keyPath isEqualToString:keyPath];
        }];
        
        NSSet *subscriptions = [self.subscriptions filteredSetUsingPredicate:predicate];
        
        if (subscriptions.count > 0) {
            success = [[_ZCRPostOffice sharedPostOffice] removeSubscriptions:subscriptions];
            
            if (success) {
                [self.subscriptions minusSet:subscriptions];
                
                // On success we need to check if the notifier should be removed from the array so it can be released
                predicate = [NSPredicate predicateWithBlock:^BOOL(_ZCRSubscription *existingSubscription, NSDictionary *__unused bindings) {
                    return existingSubscription.notifier == notifier;
                }];
                
                subscriptions = [self.subscriptions filteredSetUsingPredicate:predicate];
                
                // If no more subscriptions exist for the notifier, we can safely remove it from the array
                if (subscriptions.count == 0) {
                    [self.notifiers removeObjectAtIndex:notifierIndex];
                }
            }
        }
    }
    
    [self.lock unlock];
    
    return success;
}

- (BOOL)unsubscribeFrom:(id)notifier {
    if (!notifier) { return NO; }
    
    [self.lock lock];
    
    BOOL success = NO;
    
    NSUInteger notifierIndex = [self.notifiers indexOfObjectIdenticalTo:notifier];
    
    if (notifierIndex != NSNotFound) {
        // We need a custom predicate that checks the notifier pointers
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(_ZCRSubscription *subscription, NSDictionary *bindings) {
            return subscription.notifier == notifier;
        }];
        
        NSSet *subscriptions = [self.subscriptions filteredSetUsingPredicate:predicate];
        
        success = [[_ZCRPostOffice sharedPostOffice] removeSubscriptions:subscriptions];
        
        if (success) {
            [self.subscriptions minusSet:subscriptions];
            [self.notifiers removeObjectAtIndex:notifierIndex];
        }
    }
    
    [self.lock unlock];
    
    return success;
}

- (void)unsubscribeFromAll {
    [self.lock lock];
    
    [[_ZCRPostOffice sharedPostOffice] removeSubscriptions:self.subscriptions];
    
    [self.subscriptions removeAllObjects];
    [self.notifiers removeAllObjects];
    
    [self.lock unlock];
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

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@:%p>", NSStringFromClass([self class]), self];
    
    [self.lock lock];
    
    NSSet *subscriptions = [self.subscriptions copy];
    
    [self.lock unlock];
    
    [description appendString:@" subscriptions:("];
    
    for (_ZCRSubscription *subscription in subscriptions) {
        [description appendFormat:@"\n\t%@", subscription];
    }
    
    if (subscriptions.count > 0) {
        [description appendString:@"\n)"];
    } else {
        [description appendString:@")"];
    }
    
    return [description copy];
}

- (BOOL)addSubscription:(_ZCRSubscription *)subscription {
    if (!subscription) { return NO; }
    
    id notifier = subscription.notifier;
    
    if (!notifier) { return NO; }
    
    [self.lock lock];
    
    NSMutableSet *subscriptions = self.subscriptions;
    
    // This is highly unlikely since equality is pretty strict, but better safe than sorry!
    if ([subscriptions containsObject:subscription]) {
        [self.lock unlock];
        
        return NO;
    }
    
    [subscriptions addObject:subscription];
    
    [self.lock unlock];
    
    // Ala FBKVOController, we strip out the NSKeyValueObservingOptionInitial and perform the callback manually
    NSKeyValueObservingOptions cleanedOptions = subscription.options & ~NSKeyValueObservingOptionInitial;
    
    // For now these conditionals only apply to NSArrays, but in the future these more efficient observation methods for colletions might
    // be added, so we try and future proof here.
    if ([notifier respondsToSelector:@selector(addObserver:toObjectsAtIndexes:forKeyPath:options:context:)] &&
        [notifier respondsToSelector:@selector(removeObserver:fromObjectsAtIndexes:forKeyPath:context:)] &&
        [notifier respondsToSelector:@selector(count)]) {
        NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [notifier count])];
        [notifier addObserver:self toObjectsAtIndexes:indexes forKeyPath:subscription.keyPath
                      options:cleanedOptions
                      context:(__bridge void *)subscription];
    } else {
        [notifier addObserver:self forKeyPath:subscription.keyPath
                      options:cleanedOptions
                      context:(__bridge void *)subscription];
    }
    
    // Ala FBKVOController, we manually trigger the NSKeyValueObservingOptionInitial if present
    if (subscription.options & NSKeyValueObservingOptionInitial) {
        NSMutableDictionary *changeDictionary = [NSMutableDictionary dictionaryWithDictionary:@{NSKeyValueChangeKindKey: @(NSKeyValueChangeSetting)}];
        
        if (subscription.options & NSKeyValueObservingOptionNew) {
            id value = [notifier valueForKeyPath:subscription.keyPath];
            changeDictionary[NSKeyValueChangeNewKey] = value ?: [NSNull null];
        }
        
        [self observeValueForKeyPath:subscription.keyPath ofObject:notifier
                              change:[changeDictionary copy]
                             context:(__bridge void *)subscription];
    }
    
    return YES;
}

- (BOOL)removeSubscriptions:(NSSet *)subscriptions {
    if (subscriptions.count == 0) { return NO; }
    
    [self.lock lock];
    
    [self.subscriptions minusSet:subscriptions];
    
    [self.lock unlock];
    
    for (_ZCRSubscription *subscription in subscriptions) {
        id notifier = subscription.notifier;
        
        if (!notifier) { return NO; }
        
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
    
    return YES;
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
    
    // If we can't notify the subscriber for whatever reason, we should remove this subscription
    if (![self _notifySubscriber:subscriber ofChange:change subscription:subscription]) {
        [self removeSubscriptions:[NSSet setWithObject:subscription]];
    }
}

- (BOOL)_notifySubscriber:(id)subscriber ofChange:(NSDictionary *)change subscription:(_ZCRSubscription *)subscription {
    if (!subscriber || !change || !subscription) { return NO; }
    
    id notifier = subscription.notifier;
    ZCRMessage *message = [[ZCRMessage alloc] initWithNotifier:notifier keyPath:subscription.keyPath change:change];
    
    NSOperationQueue *messageQueue = subscription.mailbox.messageQueue;
    
    if (subscription.block) {
        if (messageQueue) {
            [messageQueue addOperationWithBlock:^{
                subscription.block(message);
            }];
        } else {
            subscription.block(message);
        }
        
        return YES;
    }
    
    if (subscription.selector) {
        NSMethodSignature *methodSignature = [subscriber methodSignatureForSelector:subscription.selector];
        NSUInteger numberOfArgs = methodSignature.numberOfArguments;
        
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        invocation.target = subscriber;
        invocation.selector = subscription.selector;
        
        if (numberOfArgs == 3) {
            // 0 = self, 1 = _cmd, 2 = message!
            [invocation setArgument:&message atIndex:2];
        } else if (numberOfArgs > 3) {
            // If there are over 3 arguments, treat the selector as invalid
            invocation = nil;
        }
        
        if (invocation) {
            if (messageQueue) {
                // The invocation operation will automatically tell the invocation to retain its arguments
                NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithInvocation:invocation];
                [messageQueue addOperation:operation];
            } else {
                [invocation invoke];
            }
            
            return YES;
        } else {
            return NO;
        }
    }
    
    // As a fallback, use the traditional KVO path
    if (messageQueue) {
        [messageQueue addOperationWithBlock:^{
            [subscriber observeValueForKeyPath:subscription.keyPath ofObject:notifier change:change context:subscription.userContext];
        }];
    } else {
        [subscriber observeValueForKeyPath:subscription.keyPath ofObject:notifier change:change context:subscription.userContext];
    }
    
    return YES;
}

@end


@implementation _ZCRSubscription

- (instancetype)initWithMailbox:(ZCRMailbox *)mailbox notifier:(id)notifier keyPath:(NSString *)keyPath
                        options:(NSKeyValueObservingOptions)options
                          block:(void (^)(ZCRMessage *))block selector:(SEL)selector context:(void *)userContext {
    if (!(self = [super init])) { return nil; }
    
    _mailbox = mailbox;
    _notifier = notifier;
    _keyPath = [keyPath copy];
    _options = options;
    
    _block = [block copy];
    _selector = selector;
    _userContext = userContext;
    
    return self;
}

- (instancetype)init {
    return [self initWithMailbox:nil notifier:nil keyPath:nil options:0 block:nil selector:NULL context:NULL];
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@:%p> ", NSStringFromClass([self class]), self];
    
    id mailbox = _mailbox;
    [description appendFormat:@"mailbox:<%@:%p> ", NSStringFromClass([mailbox class]), mailbox];
    
    id notifier = _notifier;
    [description appendFormat:@"notifier:<%@:%p> ", NSStringFromClass([notifier class]), notifier];
    
    [description appendFormat:@"keyPath:%@ ", _keyPath];
    [description appendFormat:@"options:%@", ZCRStringForKVOOptions(_options)];
    
    if (_block) {
        [description appendFormat:@" block:%p", _block];
    }
    
    if (_selector) {
        [description appendFormat:@" selector:%@", NSStringFromSelector(_selector)];
    }
    
    if (_userContext) {
        [description appendFormat:@" userContext:%p", _userContext];
    }
    
    return [description copy];
}

- (NSUInteger)hash {
    // For hashing we use the mailbox, notifier, keypath, and options, but exclude the notification actions.
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

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@:%p> ", NSStringFromClass([self class]), self];
    
    id notifier = _notifier;
    [description appendFormat:@"notifier:<%@:%p> ", NSStringFromClass([notifier class]), notifier];
    
    [description appendFormat:@"keyPath:%@ ", _keyPath];
    [description appendFormat:@"kind:%@", ZCRStringForKVOKind(_kind)];
    
    if (_newValue) {
        [description appendFormat:@" newValue:%@", _newValue];
    }
    
    if (_oldValue) {
        [description appendFormat:@" oldValue:%@", _oldValue];
    }
    
    if (_indexes) {
        [description appendFormat:@" indexes:%@", _indexes];
    }
    
    [description appendFormat:@" isPriorToChange:%@", (_isPriorToChange) ? @"YES" : @"NO"];
    
    return description;
}

@end
