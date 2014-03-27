//
//  ZCRMailbox.h
//  ZCRMailbox
//
//  Created by Zachary Radke on 3/20/14.
//  Copyright (c) 2014 Zach Radke. All rights reserved.
//

@import Foundation;

@class ZCRMessage;

/**
 *  Conveneince method for retrieving a human readable string from an NSKeyValueObservingOptions bitmask.
 *
 *  @param options The NSKeyValueObservingOptions bitmask.
 *
 *  @return A human readable representation of the options passed.
 */
FOUNDATION_EXPORT NSString *ZCRStringForKVOOptions(NSKeyValueObservingOptions options);

/**
 *  Convenience method for retrieving a human readable string from an NSKeyValueChange enum.
 *
 *  @param kind The NSKeyValueChange enum.
 *
 *  @return A human readable representation of the change kind passed.
 */
FOUNDATION_EXPORT NSString *ZCRStringForKVOKind(NSKeyValueChange kind) __attribute__((const));

/**
 *  The ZCRMailbox acts as a mediator in KVO notifications, taking a subscriber object and maintaining subscriptions to various notifier
 *  objects and their key paths.
 *
 *  A mailbox is created with a single "subscriber," which is stored weakly. Subscriptions can then be added to the mailbox, referencing
 *  a "notifier," which will publish KVO notifications, and a key-path for that notifier. Subscriptions can be removed using the various
 *  unsubscribe methods, or by simply deallocating the mailbox, which will automatically clean up any subscriptions that were made with it.
 *  Once a subscription is made, the notifier is strongly referenced by the mailbox until the subscription is removed.
 *
 *  While these objects are relatively lightweight, adding and removing subscriptions can be an expensive operation if performed recklessly,
 *  since they require locking of shared resources to ensure thread safety between all mailboxes. Therefore, they should typically be
 *  created and maintained for as long as possible.
 *
 *  ## Gotchas
 *
 *  A ZCRMailbox can maintain multiple notifiers and key-paths, but only one subscription for a single notifier and key-path. This means
 *  that the subscription methods cannot be successfully invoked with the same notifier and key-path, but different options or actions.
 *
 *  Because a mailbox only retains a weak reference to its subscriber, typically the subscriber will retain its mailbox. In such cases, it
 *  is very important to avoid retain cycles when using the block-based subscription methods. Referencing the subscriber in the block, which
 *  retains the mailbox, will result in the subscriber not being able to deallocate until the mailbox is manually nilled out.
 *
 *  For this same reason, it is inadvisable for a mailbox to subscribe to its subscriber's KVO notifications, as this will also strongly
 *  retain the subscriber, unless there is a guaranteed way to clear the association.
 *
 *  ZCRMailboxes are guaranteed to execute and deliver [ZCRMessages](ZCRMessage) in a thread-safe manner. Further control is posssible
 *  through setting the messageQueue property, which will ensure all messages are delivered on the provided NSOperationQueue. This is
 *  especially relevant if the block or method invoked upon KVO notifications is required to perform UI changes, in which case the
 *  messageQueue should be set to `[NSOperationQueue mainQueue]`.
 *
 *  ## Subclassing Notes
 *
 *  It should not be necessary to subclass ZCRMailbox, unless additional validation of subscribers, notifiers, key-paths, etc. is necessary.
 *  Subclasses should invoke the super implementations when available to ensure the observations are properly created. This is because
 *  ZCRMailbox does not directly add KVO-observation, nor does it guarantee thread safety outside of adding and removing subscriptions.
 */
@interface ZCRMailbox : NSObject

/** @name Creating and configuring mailboxes */

/**
 *  Designated initializer which generates a new mailbox for the given subscriber
 *
 *  @param subscriber The subscriber who will receive the KVO updates from various notifiers.
 *
 *  @return A new instance of the caller.
 */
- (instancetype)initWithSubscriber:(id)subscriber;

/**
 *  Returns the subscriber which registered this mailbox, or nil if the subscriber has been deallocated.
 */
@property (weak, nonatomic, readonly) id subscriber;

/**
 *  Allows control over which queue KVO notifications are sent. If set, all subscriptions will deliver their messages through the passed
 *  queue. Otherwise, no guarantees are made as to what queue notifications are delivered on.
 *
 *  @note This property affects all subscriptions of the mailbox. Even if a subscription was added with a a different messageQueue in place,
 *  once the property changes all future messages from that subscription will be delivered on the new messageQueue until it is changed.
 */
@property (strong) NSOperationQueue *messageQueue;


/** @name Subscribing to notifiers */

/**
 *  Adds a new subscription to the mailbox for the given notifier and key-path. The options passed will reflect the populated values of the
 *  [ZCRMessages](ZCRMessage) that are passed in the action block.
 *
 *  @note A mailbox can only have one subscription for a given notifier and key-path. This means that this method cannot be invoked
 *  successfully with the same notifier and key-path more than once without unregistering the notifier and key-path first.
 *
 *  @warning Beware of retain cycles in the action block. If an object retains this mailbox instance, it should take care to either avoid
 *  referencing itself in the block without weakening itself, or have a mechanism for manually de-referencing the mailbox.
 *
 *  @param notifier The object that will generate the KVO updates. This must not be nil.
 *  @param keyPath  The key-path on the notifier to observe. This must not be nil.
 *  @param options  A bitmask of KVO options for the subscription.
 *  @param block    A block which is invoked with each KVO update until the subscription is removed. This must not be nil.
 *
 *  @return YES if the subcription was successfully added, NO if it could not be added.
 */
- (BOOL)subscribeTo:(id)notifier keyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options
              block:(void (^)(ZCRMessage *message))block NS_REQUIRES_SUPER;

/**
 *  Adds a new subscription to the mailbox for the given notifier and key-path. The options passed will reflect the populated values of the
 *  [ZCRMessages](ZCRMessage) that may be sent to the passed selector.
 *
 *  The passed selector must either accept no additional arguments (aside from the hidden self and _cmd arguments), or a single ZCRMessage
 *  argument, for example:  `- (void)notifierDidChange;` and `- (void)subscriberDidReceiveMessage:(ZCRMessage *)message;`
 *
 *  Both example method definitions would be considered acceptable. No restrictions are placed on method return values, but nothing returned
 *  will be used by this class.
 *
 *  @param notifier The object that will generate the KVO updates. This must not be nil.
 *  @param keyPath  The key-path on the notifier to observe. This must not be nil.
 *  @param options  A bitmask of KVO options for the subscription.
 *  @param selector A selector existing on the subscriber that wil be invoked with each KVO update until the subscription is removed. This
 *  must not be nil, and must either accept no additional arguments or receive a single ZCRMessage argument.
 *
 *  @return YES if the subscription was added successfully, NO if it could not be added.
 */
- (BOOL)subscribeTo:(id)notifier keyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options
           selector:(SEL)selector NS_REQUIRES_SUPER;

/**
 *  Adds a new subscription to the mailbox for the given notifier and key-path. The options passed will reflect the values of the change
 *  dictionary sent to the subscriber's `observeValueForKeyPath:ofObject:change:context:` method.
 *
 *  @note This method exists mostly to ease the transition away from traditional KVO setups. The other `subscribeTo:...` methods should be
 *  preferred when possible.
 *
 *  @see subscribeTo:keyPath:options:block:
 *  @see subscribeTo:keyPath:options:selector:
 *
 *  @param notifier    The object that will generate the KVO updates. This must not be nil.
 *  @param keyPath     The key-path on the notifier to observe. This must not be nil.
 *  @param options     A bitmask of KVO options for the subscription.
 *  @param userContext Arbitrary data passed to the subscriber on KVO updates. This may be NULL.
 *
 *  @return YES if the subscription was added successfully, NO if it could not be added.
 */
- (BOOL)subscribeTo:(id)notifier keyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options
            context:(void *)userContext NS_REQUIRES_SUPER;


/** @name Unsubscribing from notifiers */

/**
 *  Removes a single subscription made to the given notifier for the given key-path in this mailbox.
 *
 *  @param notifier The object whose KVO update this mailbox subscribed to. This must not be nil.
 *  @param keyPath  The key-path on the notifier this mailbox subscribed to. This must not be nil.
 *
 *  @return YES if the subscription was removed, NO if it could not be.
 */
- (BOOL)unsubscribeFrom:(id)notifier keyPath:(NSString *)keyPath NS_REQUIRES_SUPER;

/**
 *  Removes all subscriptions made to the given notifier for this mailbox.
 *
 *  @param notifier The object whose KVO updates this mailbox subscribed to in one or more key-path subscriptions. This must not be nil.
 *
 *  @return YES if the subscriptions could be removed, NO if they could not be removed.
 */
- (BOOL)unsubscribeFrom:(id)notifier NS_REQUIRES_SUPER;

/**
 *  Removes all subscriptions for this mailbox. This method is naturally invoked when the mailbox deallocates.
 */
- (void)unsubscribeFromAll NS_REQUIRES_SUPER;

@end


/**
 *  A ZCRMessage represents an immutable KVO notification from an object. Because it only represents an individual KVO message, the
 *  properties that are populated depend largely on the options provided when registering for the KVO subscription in the first place.
 *
 *  These objects are generally created through ZCRMailbox subscriptions, but the designated initializer can be used in traditional KVO
 *  implementations to provide an easier interface for accessing message information.
 *
 *  ## Subclassing Notes
 *
 *  It should not be necessary to subclass ZCRMessage, unless you wish to change the behavior of the initializer. In such cases, the super
 *  implementation should be invoked.
 */
@interface ZCRMessage : NSObject {
@protected
    // These variables are exposed for subclasses.
    __weak id _notifier;
    NSString *_keyPath;
    NSKeyValueChange _kind;
    id _oldValue;
    id _newValue;
    NSIndexSet *_indexes;
    BOOL _isPriorToChange;
    
}

/**
 *  Returns the object which posted the KVO notification, or nil if the object has been deallocated.
 */
@property (weak, nonatomic, readonly) id notifier;

/**
 *  Returns the key path that was changed.
 */
@property (strong, nonatomic, readonly) NSString *keyPath;

/**
 *  Returns the type of KVO change that occured.
 */
@property (assign, nonatomic, readonly) NSKeyValueChange kind;

/**
 *  Returns the previous value of the key path, if present and subscribed for.
 */
@property (strong, nonatomic, readonly) id oldValue;

/**
 *  Returns the new value of the key path, if present and subscribed for. Note that this has the NS_RETURNS_NOT_RETAINED because it uses
 *  the reserved word "new", but does not actually increment the retain count as expected.
 */
@property (strong, nonatomic, readonly) id newValue __attribute__((ns_returns_not_retained));

/**
 *  Returns the indexes that were updated, if present and subscribed for.
 */
@property (strong, nonatomic, readonly) NSIndexSet *indexes;

/**
 *  Returns YES if this message is posted prior to the notifier making the change described, or NO if it is posted after. Note that this
 *  will only ever return YES if the KVO subscription included the NSKeyValueObservingOptionPrior option.
 */
@property (assign, nonatomic, readonly) BOOL isPriorToChange;

/**
 *  Designated initializer which uses KVO information to generate a new instance. If any of the predefined KVO change dictionary keys return
 *  an NSNull value, it will be converted automatically into nil.
 *
 *  @param notifier The object which is posting the KVO notification.
 *  @param keyPath  The key path being changed.
 *  @param change   An NSDictionary describing the change, using pre-defined KVO keys.
 *
 *  @return A populated instance of the caller.
 */
- (instancetype)initWithNotifier:(id)notifier keyPath:(NSString *)keyPath change:(NSDictionary *)change;

@end
