# Changes, logged

## 0.1.3

*March 27, 2014*

Gives control over message queues and fixes documentation issues for [appledoc](https://github.com/tomaz/appledoc).

* Adds `messageQueue` property to `ZCRMailbox` with additional tests for the new functionality.
* Fixes documentation issues with `ZCRMailbox` and `ZCRMessage`.
* Does some behind-the-scenes refactoring of `ZCRMailbox`

## 0.1.2

*March 25, 2014*

Additional subscription methods and tests.

* Adds `-subscribeTo:keyPath:options:selector` and `-subscribeTo:keyPath:options:context:` methods to `ZCRMailbox`.
* Adds `__attribute__` decorators to methods.
* Exposes `ZCRStringForKVOOptions(NSKeyValueObservingOptions)` and `ZCRStringForKVOKind(NSKeyValueChange)`.
* Adds additional tests for `ZCRMailbox` and `ZCRMessage`.

## 0.1.1

*March 25, 2014*

Bug fixes, organizational fixes, debugging enhancements.

* Adds this change log!
* Adds `-description` methods to all classes for easier debugging.
* Fixes a bug with `-unsubscribeFrom:keyPath:` where the notifier would not be released even if all its subscriptions had been cancelled. Also adds tests to make sure this doesn't happen again!
* Shifts some methods around for better logic flow.
* Takes another page out of [FBKVOController](https://github.com/facebook/KVOController/blob/7742b9c81e528f0df6deea7fd3df9cc7ce3a9e8c/FBKVOController/FBKVOController.m#L268) and manually performs the `NSKeyValueObeservingOptionInitial` callback.


## 0.1.0

*March 24, 2014*

Initial release.

* Adds `ZCRMailbox` and `ZCRMessage` classes.
* Adds unit tests for `ZCRMailbox`.
* Integrates unit tests into [Travis CI](https://travis-ci.org/zradke/ZCRMailbox)

