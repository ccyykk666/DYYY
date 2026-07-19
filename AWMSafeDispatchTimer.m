#import "AWMSafeDispatchTimer.h"


static const void *kAWMSafeDispatchTimerSpecificKey = &kAWMSafeDispatchTimerSpecificKey;

@interface AWMSafeDispatchTimer ()
@property (nonatomic, strong, nullable) dispatch_source_t internalTimer;
@property (nonatomic, assign) BOOL resumed;
@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@property (nonatomic, assign, getter=isRunning) BOOL running;
- (void)cancelLocked;
- (BOOL)isCurrentTimerIdentity:(uintptr_t)timerIdentity;
- (void)cancelTimerIfCurrentIdentity:(uintptr_t)timerIdentity;
@end

@implementation AWMSafeDispatchTimer

- (instancetype)init {
    self = [super init];
    if (self) {
        _synchronizationQueue = dispatch_queue_create("com.dyyy.safeDispatchTimer", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_synchronizationQueue, kAWMSafeDispatchTimerSpecificKey, (__bridge void *)self, NULL);
    }
    return self;
}

- (void)startWithInterval:(NSTimeInterval)interval
                   leeway:(NSTimeInterval)leeway
                    queue:(dispatch_queue_t)queue
                 repeats:(BOOL)repeats
                 handler:(dispatch_block_t)handler {
    if (interval <= 0.0) {
        interval = 0.1;
    }
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC));
    uint64_t repeatInterval = repeats ? (uint64_t)(interval * NSEC_PER_SEC) : DISPATCH_TIME_FOREVER;
    uint64_t tolerance = leeway > 0 ? (uint64_t)(leeway * NSEC_PER_SEC) : (uint64_t)(0.1 * NSEC_PER_SEC);

    __weak __typeof(self) weakSelf = self;
    dispatch_async(self.synchronizationQueue, ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          return;
      }

      [strongSelf cancelLocked];

      dispatch_queue_t targetQueue = queue ?: dispatch_get_main_queue();
      dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, targetQueue);
      if (!timer) {
          return;
      }

      strongSelf.internalTimer = timer;
      dispatch_block_t eventBlock = [handler copy];
      uintptr_t timerIdentity = (uintptr_t)(__bridge void *)timer;

      dispatch_source_set_timer(timer, startTime, repeatInterval, tolerance);
      dispatch_source_set_event_handler(timer, ^{
        __strong __typeof(weakSelf) innerSelf = weakSelf;
        if (!innerSelf || ![innerSelf isCurrentTimerIdentity:timerIdentity]) {
            return;
        }
        if (eventBlock) {
            eventBlock();
        }
        if (!repeats) {
            [innerSelf cancelTimerIfCurrentIdentity:timerIdentity];
        }
      });

      if (!strongSelf.resumed) {
          dispatch_resume(timer);
          strongSelf.resumed = YES;
      }

      strongSelf.running = YES;
    });
}

- (void)cancel {
    dispatch_async(self.synchronizationQueue, ^{
      [self cancelLocked];
    });
}

- (void)cancelLocked {
    if (!self.internalTimer) {
        return;
    }

    dispatch_source_t timer = self.internalTimer;
    self.internalTimer = nil;

    dispatch_source_set_event_handler(timer, ^{});

    if (self.resumed) {
        dispatch_source_cancel(timer);
        self.resumed = NO;
    }

    self.running = NO;
}

- (BOOL)isCurrentTimerIdentity:(uintptr_t)timerIdentity {
    if (dispatch_get_specific(kAWMSafeDispatchTimerSpecificKey) == (__bridge void *)self) {
        return (uintptr_t)(__bridge void *)self.internalTimer == timerIdentity;
    }

    __block BOOL isCurrent = NO;
    dispatch_sync(self.synchronizationQueue, ^{
      isCurrent = (uintptr_t)(__bridge void *)self.internalTimer == timerIdentity;
    });
    return isCurrent;
}

- (void)cancelTimerIfCurrentIdentity:(uintptr_t)timerIdentity {
    dispatch_async(self.synchronizationQueue, ^{
      if ((uintptr_t)(__bridge void *)self.internalTimer == timerIdentity) {
          [self cancelLocked];
      }
    });
}

- (BOOL)isRunning {
    if (dispatch_get_specific(kAWMSafeDispatchTimerSpecificKey) == (__bridge void *)self) {
        return _running;
    }

    __block BOOL runningState = NO;
    dispatch_sync(self.synchronizationQueue, ^{
      runningState = _running;
    });
    return runningState;
}

- (void)dealloc {
    // dealloc 中不能再通过 -cancel 异步捕获 self；对象析构完成后，
    // 排队的 block 会向已释放实例发送 -cancelLocked，造成野指针崩溃。
    dispatch_source_t timer = _internalTimer;
    _internalTimer = nil;

    if (timer) {
        dispatch_source_set_event_handler(timer, ^{});
        if (_resumed) {
            dispatch_source_cancel(timer);
        }
    }

    _resumed = NO;
    _running = NO;

    if (_synchronizationQueue) {
        dispatch_queue_set_specific(_synchronizationQueue, kAWMSafeDispatchTimerSpecificKey, NULL, NULL);
    }
}

@end
