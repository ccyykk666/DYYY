#import "DYYYDiagnostics.h"

#import <mach-o/dyld.h>
#import <math.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>

#import "DYYYConstants.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"

NSString *const DYYYDiagnosticsGestureEnabledKey = @"DYYYDiagnosticsGestureEnabled";
NSString *const DYYYDiagnosticsGestureProfileKey = @"DYYYDiagnosticsGestureProfile";
NSString *const DYYYDiagnosticsIncludeTextKey = @"DYYYDiagnosticsIncludeText";
NSString *const DYYYDiagnosticsIncludeScreenshotKey = @"DYYYDiagnosticsIncludeScreenshot";
NSString *const DYYYDiagnosticsIncludeConstraintsKey = @"DYYYDiagnosticsIncludeConstraints";
NSString *const DYYYDiagnosticsIncludeRuntimeKey = @"DYYYDiagnosticsIncludeRuntime";

static NSString *const kDYYYDiagnosticsErrorDomain = @"com.dyyy.diagnostics";
static NSString *const kDYYYDiagnosticsLatestBaseNameKey = @"DYYYDiagnosticsLatestBaseName";
static NSString *const kDYYYDiagnosticsSourceBaseline = @"Wtrwx/DYYY@034b243";
static const NSUInteger kDYYYDiagnosticsMaximumViewNodes = 6000;
static const NSUInteger kDYYYDiagnosticsMaximumViewDepth = 45;
static const NSUInteger kDYYYDiagnosticsMaximumRuntimeNames = 3000;
static const NSUInteger kDYYYDiagnosticsMaximumRuntimeDetails = 320;
static char kDYYYDiagnosticsGestureAssociationKey;

@interface DYYYDiagnosticsCollector ()

@property(nonatomic, strong) dispatch_queue_t workQueue;
@property(nonatomic, assign) BOOL collecting;

@end

@implementation DYYYDiagnosticsCollector

#pragma mark - Lifecycle and preferences

+ (instancetype)sharedCollector {
    static DYYYDiagnosticsCollector *collector = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      collector = [[DYYYDiagnosticsCollector alloc] init];
    });
    return collector;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _workQueue = dispatch_queue_create("com.dyyy.diagnostics.collector", DISPATCH_QUEUE_SERIAL);
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults objectForKey:DYYYDiagnosticsIncludeConstraintsKey] == nil) {
            [defaults setBool:YES forKey:DYYYDiagnosticsIncludeConstraintsKey];
        }
        if ([defaults objectForKey:DYYYDiagnosticsIncludeRuntimeKey] == nil) {
            [defaults setBool:YES forKey:DYYYDiagnosticsIncludeRuntimeKey];
        }
        if ([defaults objectForKey:DYYYDiagnosticsGestureProfileKey] == nil) {
            [defaults setInteger:DYYYDiagnosticsProfileCommentPanel forKey:DYYYDiagnosticsGestureProfileKey];
        }
    }
    return self;
}

+ (BOOL)captureGestureEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:DYYYDiagnosticsGestureEnabledKey];
}

+ (void)setCaptureGestureEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:DYYYDiagnosticsGestureEnabledKey];
    [self syncCaptureGestureForAllWindows];
}

+ (DYYYDiagnosticsProfile)captureGestureProfile {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:DYYYDiagnosticsGestureProfileKey] == nil) {
        return DYYYDiagnosticsProfileCommentPanel;
    }
    NSInteger rawValue = [defaults integerForKey:DYYYDiagnosticsGestureProfileKey];
    return rawValue == DYYYDiagnosticsProfileGeneral ? DYYYDiagnosticsProfileGeneral : DYYYDiagnosticsProfileCommentPanel;
}

+ (void)setCaptureGestureProfile:(DYYYDiagnosticsProfile)profile {
    [[NSUserDefaults standardUserDefaults] setInteger:profile forKey:DYYYDiagnosticsGestureProfileKey];
}

+ (BOOL)includeVisibleText {
    return [[NSUserDefaults standardUserDefaults] boolForKey:DYYYDiagnosticsIncludeTextKey];
}

+ (void)setIncludeVisibleText:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:DYYYDiagnosticsIncludeTextKey];
}

+ (BOOL)includeScreenshot {
    return [[NSUserDefaults standardUserDefaults] boolForKey:DYYYDiagnosticsIncludeScreenshotKey];
}

+ (void)setIncludeScreenshot:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:DYYYDiagnosticsIncludeScreenshotKey];
}

+ (BOOL)includeConstraints {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:DYYYDiagnosticsIncludeConstraintsKey] == nil ? YES : [defaults boolForKey:DYYYDiagnosticsIncludeConstraintsKey];
}

+ (void)setIncludeConstraints:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:DYYYDiagnosticsIncludeConstraintsKey];
}

+ (BOOL)includeRuntimeDetails {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:DYYYDiagnosticsIncludeRuntimeKey] == nil ? YES : [defaults boolForKey:DYYYDiagnosticsIncludeRuntimeKey];
}

+ (void)setIncludeRuntimeDetails:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:DYYYDiagnosticsIncludeRuntimeKey];
}

#pragma mark - Gesture

+ (NSArray<UIWindow *> *)applicationWindows {
    NSAssert([NSThread isMainThread], @"Window collection must run on the main thread");
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window && ![windows containsObject:window]) {
                    [windows addObject:window];
                }
            }
        }
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window && ![windows containsObject:window]) {
            [windows addObject:window];
        }
    }
    return windows;
}

+ (void)syncCaptureGestureForAllWindows {
    dispatch_async(dispatch_get_main_queue(), ^{
      for (UIWindow *window in [self applicationWindows]) {
          [self syncCaptureGestureForWindow:window];
      }
    });
}

+ (void)syncCaptureGestureForWindow:(UIWindow *)window {
    if (!window || ![NSThread isMainThread]) {
        if (window) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [self syncCaptureGestureForWindow:window];
            });
        }
        return;
    }

    UILongPressGestureRecognizer *existing = objc_getAssociatedObject(window, &kDYYYDiagnosticsGestureAssociationKey);
    BOOL shouldInstall = [self captureGestureEnabled] && window.rootViewController != nil && window.windowLevel == UIWindowLevelNormal;
    if (!shouldInstall) {
        if (existing) {
            [window removeGestureRecognizer:existing];
            objc_setAssociatedObject(window, &kDYYYDiagnosticsGestureAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (existing) {
        return;
    }

    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:[self sharedCollector] action:@selector(handleCaptureGesture:)];
    gesture.numberOfTouchesRequired = 4;
    gesture.minimumPressDuration = 0.9;
    gesture.cancelsTouchesInView = NO;
    gesture.delaysTouchesBegan = NO;
    gesture.delaysTouchesEnded = NO;
    [window addGestureRecognizer:gesture];
    objc_setAssociatedObject(window, &kDYYYDiagnosticsGestureAssociationKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)handleCaptureGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    [self collectCurrentStateWithProfile:[DYYYDiagnosticsCollector captureGestureProfile]
                              completion:^(NSArray<NSURL *> *fileURLs, NSError *error) {
                                if (error) {
                                    [DYYYUtils showToast:[NSString stringWithFormat:@"诊断采集失败：%@", error.localizedDescription]];
                                } else {
                                    [DYYYToast showSuccessToastWithMessage:[NSString stringWithFormat:@"诊断采集完成（%lu 个文件）", (unsigned long)fileURLs.count]];
                                }
                              }];
}

#pragma mark - Report files

+ (NSURL *)reportsDirectoryURL {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
    NSURL *directoryURL = [NSURL fileURLWithPath:[documents stringByAppendingPathComponent:@"DYYYDiagnostics"] isDirectory:YES];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:&error];
    if (!error) {
        [directoryURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    }
    return directoryURL;
}

+ (NSArray<NSURL *> *)latestReportFileURLs {
    NSString *baseName = [[NSUserDefaults standardUserDefaults] stringForKey:kDYYYDiagnosticsLatestBaseNameKey];
    if (baseName.length == 0) {
        return @[];
    }
    NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self reportsDirectoryURL]
                                                            includingPropertiesForKeys:@[ NSURLContentModificationDateKey ]
                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                 error:nil];
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
      return [url.lastPathComponent hasPrefix:baseName];
    }];
    return [[files filteredArrayUsingPredicate:predicate] sortedArrayUsingComparator:^NSComparisonResult(NSURL *lhs, NSURL *rhs) {
      return [lhs.pathExtension compare:rhs.pathExtension options:NSCaseInsensitiveSearch];
    }];
}

+ (NSUInteger)reportCount {
    NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self reportsDirectoryURL]
                                                            includingPropertiesForKeys:nil
                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                 error:nil];
    return [[files filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
                    return [url.pathExtension.lowercaseString isEqualToString:@"json"];
                  }]] count];
}

+ (unsigned long long)reportsSize {
    NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[self reportsDirectoryURL]
                                                                     includingPropertiesForKeys:@[ NSURLFileSizeKey ]
                                                                                        options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                   errorHandler:nil];
    unsigned long long total = 0;
    for (NSURL *url in enumerator) {
        NSNumber *fileSize = nil;
        [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        total += fileSize.unsignedLongLongValue;
    }
    return total;
}

+ (BOOL)clearReports:(NSError **)error {
    NSURL *directoryURL = [self reportsDirectoryURL];
    NSError *listError = nil;
    NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directoryURL
                                                            includingPropertiesForKeys:nil
                                                                               options:0
                                                                                 error:&listError];
    if (!files) {
        if (error) {
            *error = listError;
        }
        return NO;
    }
    for (NSURL *url in files) {
        NSError *removeError = nil;
        if (![[NSFileManager defaultManager] removeItemAtURL:url error:&removeError]) {
            if (error) {
                *error = removeError;
            }
            return NO;
        }
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDYYYDiagnosticsLatestBaseNameKey];
    return YES;
}

#pragma mark - Collection entry point

- (void)collectCurrentStateWithProfile:(DYYYDiagnosticsProfile)profile completion:(DYYYDiagnosticsCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
      @synchronized(self) {
          if (self.collecting) {
              NSError *error = [NSError errorWithDomain:kDYYYDiagnosticsErrorDomain
                                                   code:1
                                               userInfo:@{NSLocalizedDescriptionKey : @"已有诊断任务正在运行"}];
              if (completion) {
                  completion(nil, error);
              }
              return;
          }
          self.collecting = YES;
      }

      NSData *screenshotData = nil;
      NSMutableSet<NSString *> *visibleClassNames = [NSMutableSet set];
      NSDictionary *uiSnapshot = [self captureUIStateForProfile:profile visibleClassNames:visibleClassNames screenshotData:&screenshotData];
      NSDictionary *metadata = [self captureMetadataForProfile:profile];
      NSDictionary *settings = [self captureDYYYSettingsSummary];
      [DYYYUtils showToast:@"正在整理诊断数据…"];

      dispatch_async(self.workQueue, ^{
        @autoreleasepool {
            NSMutableDictionary *report = [NSMutableDictionary dictionary];
            report[@"schemaVersion"] = @1;
            report[@"metadata"] = metadata;
            report[@"dyyySettings"] = settings;
            report[@"ui"] = uiSnapshot;
            report[@"runtime"] = [DYYYDiagnosticsCollector includeRuntimeDetails] ? [self captureRuntimeForVisibleClassNames:visibleClassNames] : @{@"included" : @NO};

            NSError *writeError = nil;
            NSArray<NSURL *> *fileURLs = [self writeReport:report screenshotData:screenshotData profile:profile error:&writeError];
            dispatch_async(dispatch_get_main_queue(), ^{
              @synchronized(self) {
                  self.collecting = NO;
              }
              if (completion) {
                  completion(fileURLs.count > 0 ? fileURLs : nil, writeError);
              }
            });
        }
      });
    });
}

#pragma mark - Metadata and privacy

- (NSDictionary *)captureMetadataForProfile:(DYYYDiagnosticsProfile)profile {
    NSBundle *bundle = [NSBundle mainBundle];
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    UIScreen *screen = [UIScreen mainScreen];
    UIDevice *device = [UIDevice currentDevice];
    return @{
        @"timestamp" : [self ISO8601Timestamp],
        @"profile" : profile == DYYYDiagnosticsProfileCommentPanel ? @"commentPanel" : @"general",
        @"sourceBaseline" : kDYYYDiagnosticsSourceBaseline,
        @"pluginVersion" : DYYY_VERSION,
        @"app" : @{
            @"bundleIdentifier" : bundle.bundleIdentifier ?: @"",
            @"version" : [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
            @"build" : [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
        },
        @"device" : @{
            @"model" : device.model ?: @"",
            @"hardware" : [self hardwareMachine],
            @"systemName" : device.systemName ?: @"",
            @"systemVersion" : device.systemVersion ?: @"",
            @"idiom" : @(device.userInterfaceIdiom),
            @"screenBounds" : [self rectDictionary:screen.bounds],
            @"screenScale" : @(screen.scale),
        },
        @"process" : @{
            @"pid" : @(processInfo.processIdentifier),
            @"processorCount" : @(processInfo.processorCount),
            @"physicalMemory" : @(processInfo.physicalMemory),
            @"systemUptime" : @(processInfo.systemUptime),
            @"lowPowerMode" : @(processInfo.lowPowerModeEnabled),
        },
        @"packageEnvironment" : [self packageEnvironment],
        @"privacy" : @{
            @"visibleTextIncluded" : @([DYYYDiagnosticsCollector includeVisibleText]),
            @"screenshotIncluded" : @([DYYYDiagnosticsCollector includeScreenshot]),
            @"constraintsIncluded" : @([DYYYDiagnosticsCollector includeConstraints]),
            @"runtimeDetailsIncluded" : @([DYYYDiagnosticsCollector includeRuntimeDetails]),
            @"credentialsCollected" : @NO,
            @"nonDYYYPreferencesCollected" : @NO,
        },
    };
}

- (NSDictionary *)packageEnvironment {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *paths = @[
        @"/var/jb",
        @"/var/containers/Bundle/tweaksupport",
        @"/Library/MobileSubstrate",
        @"/usr/lib/libhooker.dylib",
        @"/usr/lib/substitute-inserter.dylib",
    ];
    NSMutableDictionary *indicators = [NSMutableDictionary dictionary];
    for (NSString *path in paths) {
        indicators[path] = @([fileManager fileExistsAtPath:path]);
    }
    return @{@"filesystemIndicators" : indicators};
}

- (NSDictionary *)captureDYYYSettingsSummary {
    NSDictionary *allValues = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSMutableDictionary *summary = [NSMutableDictionary dictionary];
    for (NSString *key in [[allValues allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if (![key hasPrefix:@"DYYY"]) {
            continue;
        }
        id value = allValues[key];
        if ([value isKindOfClass:[NSNumber class]]) {
            summary[key] = value;
        } else if ([value isKindOfClass:[NSString class]]) {
            summary[key] = @{@"type" : @"string", @"length" : @([(NSString *)value length]), @"valueRedacted" : @YES};
        } else if ([value isKindOfClass:[NSArray class]]) {
            summary[key] = @{@"type" : @"array", @"count" : @([(NSArray *)value count]), @"valueRedacted" : @YES};
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            summary[key] = @{@"type" : @"dictionary", @"count" : @([(NSDictionary *)value count]), @"valueRedacted" : @YES};
        } else if (value) {
            summary[key] = @{@"type" : NSStringFromClass([value class]), @"valueRedacted" : @YES};
        }
    }
    return summary;
}

- (NSString *)ISO8601Timestamp {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    return [formatter stringFromDate:[NSDate date]];
}

- (NSString *)hardwareMachine {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size == 0) {
        return @"";
    }
    char *machine = calloc(1, size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *result = [NSString stringWithUTF8String:machine] ?: @"";
    free(machine);
    return result;
}

#pragma mark - UI snapshot

- (NSDictionary *)captureUIStateForProfile:(DYYYDiagnosticsProfile)profile
                         visibleClassNames:(NSMutableSet<NSString *> *)visibleClassNames
                            screenshotData:(NSData **)screenshotData {
    NSAssert([NSThread isMainThread], @"UI capture must run on the main thread");
    NSArray<UIWindow *> *windows = [DYYYDiagnosticsCollector applicationWindows];
    NSMutableArray *windowNodes = [NSMutableArray array];
    NSMutableArray *candidates = [NSMutableArray array];
    NSUInteger nodeCount = 0;

    [windows enumerateObjectsUsingBlock:^(UIWindow *window, NSUInteger index, BOOL *stop) {
      NSString *windowPath = [NSString stringWithFormat:@"window[%lu]", (unsigned long)index];
      NSMutableDictionary *windowNode = [[self viewNodeForView:window
                                                         path:windowPath
                                                        depth:0
                                                      profile:profile
                                                 candidates:candidates
                                          visibleClassNames:visibleClassNames
                                                   nodeCount:&nodeCount] mutableCopy];
      windowNode[@"window"] = @{
          @"keyWindow" : @(window.isKeyWindow),
          @"windowLevel" : @(window.windowLevel),
          @"screenBounds" : [self rectDictionary:window.screen.bounds],
          @"rootViewController" : window.rootViewController ? [self controllerNode:window.rootViewController
                                                                          visited:[NSHashTable weakObjectsHashTable]
                                                                visibleClassNames:visibleClassNames] : [NSNull null],
      };
      [windowNodes addObject:windowNode];
    }];

    if ([DYYYDiagnosticsCollector includeScreenshot] && screenshotData) {
        *screenshotData = [self screenshotDataForWindows:windows];
    }

    return @{
        @"nodeCount" : @(nodeCount),
        @"maximumNodeCount" : @(kDYYYDiagnosticsMaximumViewNodes),
        @"truncated" : @(nodeCount >= kDYYYDiagnosticsMaximumViewNodes),
        @"windows" : windowNodes,
        @"candidates" : candidates,
    };
}

- (NSDictionary *)viewNodeForView:(UIView *)view
                             path:(NSString *)path
                            depth:(NSUInteger)depth
                          profile:(DYYYDiagnosticsProfile)profile
                       candidates:(NSMutableArray *)candidates
                visibleClassNames:(NSMutableSet<NSString *> *)visibleClassNames
                        nodeCount:(NSUInteger *)nodeCount {
    if (!view || !nodeCount || *nodeCount >= kDYYYDiagnosticsMaximumViewNodes) {
        return @{@"truncated" : @YES};
    }
    (*nodeCount)++;

    NSString *className = NSStringFromClass([view class]) ?: @"";
    [visibleClassNames addObject:className];
    NSArray<NSDictionary *> *textEntries = [self textEntriesForView:view];
    NSMutableArray<NSString *> *matchInputs = [NSMutableArray arrayWithObject:className];
    for (NSDictionary *entry in textEntries) {
        NSString *rawValue = entry[@"rawValue"];
        if (rawValue.length > 0) {
            [matchInputs addObject:rawValue];
        }
    }
    if (view.accessibilityLabel.length > 0) {
        [matchInputs addObject:view.accessibilityLabel];
    }
    if (view.accessibilityIdentifier.length > 0) {
        [matchInputs addObject:view.accessibilityIdentifier];
    }
    NSArray<NSString *> *matches = [self matchedKeywordsForStrings:matchInputs profile:profile];

    NSMutableDictionary *node = [@{
        @"class" : className,
        @"superclass" : NSStringFromClass(class_getSuperclass([view class])) ?: @"",
        @"address" : [NSString stringWithFormat:@"%p", view],
        @"path" : path,
        @"depth" : @(depth),
        @"frame" : [self rectDictionary:view.frame],
        @"bounds" : [self rectDictionary:view.bounds],
        @"center" : @{@"x" : @(view.center.x), @"y" : @(view.center.y)},
        @"alpha" : @(view.alpha),
        @"hidden" : @(view.hidden),
        @"opaque" : @(view.opaque),
        @"userInteractionEnabled" : @(view.userInteractionEnabled),
        @"tag" : @(view.tag),
        @"contentMode" : @(view.contentMode),
        @"translatesAutoresizingMaskIntoConstraints" : @(view.translatesAutoresizingMaskIntoConstraints),
        @"safeAreaInsets" : [self edgeInsetsDictionary:view.safeAreaInsets],
        @"layoutMargins" : [self edgeInsetsDictionary:view.layoutMargins],
        @"transform" : @{
            @"a" : @(view.transform.a),
            @"b" : @(view.transform.b),
            @"c" : @(view.transform.c),
            @"d" : @(view.transform.d),
            @"tx" : @(view.transform.tx),
            @"ty" : @(view.transform.ty),
        },
        @"layer" : @{
            @"class" : NSStringFromClass([view.layer class]) ?: @"",
            @"cornerRadius" : @(view.layer.cornerRadius),
            @"masksToBounds" : @(view.layer.masksToBounds),
            @"zPosition" : @(view.layer.zPosition),
        },
        @"textEntries" : [self sanitizedTextEntries:textEntries],
        @"accessibility" : [self accessibilityDictionaryForView:view],
        @"keywordMatches" : matches,
        @"gestures" : [self gestureDictionariesForView:view],
    } mutableCopy];

    if ([view isKindOfClass:[UIControl class]]) {
        node[@"control"] = [self controlDictionary:(UIControl *)view];
    }
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)view;
        node[@"scrollView"] = @{
            @"contentOffset" : @{@"x" : @(scrollView.contentOffset.x), @"y" : @(scrollView.contentOffset.y)},
            @"contentSize" : @{@"width" : @(scrollView.contentSize.width), @"height" : @(scrollView.contentSize.height)},
            @"contentInset" : [self edgeInsetsDictionary:scrollView.contentInset],
            @"adjustedContentInset" : [self edgeInsetsDictionary:scrollView.adjustedContentInset],
            @"scrollEnabled" : @(scrollView.scrollEnabled),
        };
    }
    if ([DYYYDiagnosticsCollector includeConstraints]) {
        node[@"constraints"] = [self constraintDictionariesForView:view];
    }

    if (matches.count > 0) {
        [candidates addObject:@{
            @"path" : path,
            @"class" : className,
            @"address" : [NSString stringWithFormat:@"%p", view],
            @"keywordMatches" : matches,
            @"responderChain" : [self responderChainForResponder:view],
        }];
    }

    NSMutableArray *children = [NSMutableArray array];
    if (depth < kDYYYDiagnosticsMaximumViewDepth) {
        [view.subviews enumerateObjectsUsingBlock:^(UIView *subview, NSUInteger index, BOOL *stop) {
          if (*nodeCount >= kDYYYDiagnosticsMaximumViewNodes) {
              *stop = YES;
              return;
          }
          NSString *childPath = [path stringByAppendingFormat:@"/%@[%lu]", NSStringFromClass([subview class]), (unsigned long)index];
          [children addObject:[self viewNodeForView:subview
                                              path:childPath
                                             depth:depth + 1
                                           profile:profile
                                        candidates:candidates
                                 visibleClassNames:visibleClassNames
                                         nodeCount:nodeCount]];
        }];
    } else if (view.subviews.count > 0) {
        node[@"depthTruncated"] = @YES;
    }
    node[@"children"] = children;
    return node;
}

- (NSDictionary *)controllerNode:(UIViewController *)controller
                         visited:(NSHashTable *)visited
               visibleClassNames:(NSMutableSet<NSString *> *)visibleClassNames {
    if (!controller || [visited containsObject:controller]) {
        return @{@"cycle" : @YES};
    }
    [visited addObject:controller];
    NSString *className = NSStringFromClass([controller class]) ?: @"";
    [visibleClassNames addObject:className];
    NSMutableArray *children = [NSMutableArray array];
    for (UIViewController *child in controller.childViewControllers) {
        [children addObject:[self controllerNode:child visited:visited visibleClassNames:visibleClassNames]];
    }
    if (controller.presentedViewController) {
        [children addObject:[self controllerNode:controller.presentedViewController visited:visited visibleClassNames:visibleClassNames]];
    }
    return @{
        @"class" : className,
        @"address" : [NSString stringWithFormat:@"%p", controller],
        @"title" : [self textDescriptor:controller.title],
        @"viewLoaded" : @(controller.isViewLoaded),
        @"viewAppeared" : @(controller.viewIfLoaded.window != nil),
        @"modalPresentationStyle" : @(controller.modalPresentationStyle),
        @"parentClass" : controller.parentViewController ? NSStringFromClass([controller.parentViewController class]) : @"",
        @"presentingClass" : controller.presentingViewController ? NSStringFromClass([controller.presentingViewController class]) : @"",
        @"children" : children,
    };
}

- (NSArray<NSDictionary *> *)textEntriesForView:(UIView *)view {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = ((UILabel *)view).text;
        if (text.length > 0) {
            [entries addObject:@{@"source" : @"UILabel.text", @"rawValue" : text}];
        }
    }
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        for (NSNumber *stateNumber in @[ @(UIControlStateNormal), @(UIControlStateSelected), @(UIControlStateDisabled) ]) {
            NSString *title = [button titleForState:stateNumber.unsignedIntegerValue];
            if (title.length > 0) {
                [entries addObject:@{@"source" : [NSString stringWithFormat:@"UIButton.title[%@]", stateNumber], @"rawValue" : title}];
            }
        }
    }
    if ([view isKindOfClass:[UITextField class]] && ((UITextField *)view).text.length > 0) {
        [entries addObject:@{@"source" : @"UITextField.text", @"rawValue" : ((UITextField *)view).text}];
    }
    if ([view isKindOfClass:[UITextView class]] && ((UITextView *)view).text.length > 0) {
        [entries addObject:@{@"source" : @"UITextView.text", @"rawValue" : ((UITextView *)view).text}];
    }
    if ([view isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *segmentedControl = (UISegmentedControl *)view;
        for (NSInteger index = 0; index < segmentedControl.numberOfSegments; index++) {
            NSString *title = [segmentedControl titleForSegmentAtIndex:index];
            if (title.length > 0) {
                [entries addObject:@{@"source" : [NSString stringWithFormat:@"UISegmentedControl.title[%ld]", (long)index], @"rawValue" : title}];
            }
        }
    }
    return entries;
}

- (NSArray<NSDictionary *> *)sanitizedTextEntries:(NSArray<NSDictionary *> *)entries {
    NSMutableArray *sanitized = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        NSMutableDictionary *value = [[self textDescriptor:entry[@"rawValue"]] mutableCopy];
        value[@"source"] = entry[@"source"] ?: @"";
        [sanitized addObject:value];
    }
    return sanitized;
}

- (NSDictionary *)textDescriptor:(NSString *)text {
    if (text.length == 0) {
        return @{@"length" : @0};
    }
    NSMutableDictionary *descriptor = [@{@"length" : @(text.length)} mutableCopy];
    NSArray *keywords = [self matchedKeywordsForStrings:@[ text ] profile:DYYYDiagnosticsProfileCommentPanel];
    if (keywords.count > 0) {
        descriptor[@"keywordMatches"] = keywords;
    }
    if ([DYYYDiagnosticsCollector includeVisibleText]) {
        descriptor[@"value"] = text;
    } else {
        descriptor[@"valueRedacted"] = @YES;
    }
    return descriptor;
}

- (NSDictionary *)accessibilityDictionaryForView:(UIView *)view {
    return @{
        @"isElement" : @(view.isAccessibilityElement),
        @"label" : [self textDescriptor:view.accessibilityLabel],
        @"identifier" : [self textDescriptor:view.accessibilityIdentifier],
        @"value" : [self textDescriptor:[view.accessibilityValue isKindOfClass:[NSString class]] ? view.accessibilityValue : nil],
        @"hint" : [self textDescriptor:view.accessibilityHint],
        @"traits" : @(view.accessibilityTraits),
    };
}

- (NSArray<NSString *> *)matchedKeywordsForStrings:(NSArray<NSString *> *)strings profile:(DYYYDiagnosticsProfile)profile {
    NSArray<NSString *> *keywords = profile == DYYYDiagnosticsProfileCommentPanel
                                        ? @[ @"AI", @"AIGC", @"解析", @"智能", @"总结", @"评论", @"comment", @"analysis", @"assistant", @"copilot", @"explain", @"segment", @"tab", @"panel", @"header", @"insight" ]
                                        : @[ @"AI", @"AIGC", @"comment", @"analysis", @"assistant", @"copilot", @"segment", @"tab", @"panel", @"header", @"controller", @"ABTest", @"experiment" ];
    NSMutableOrderedSet<NSString *> *matches = [NSMutableOrderedSet orderedSet];
    for (NSString *candidate in strings) {
        if (![candidate isKindOfClass:[NSString class]] || candidate.length == 0) {
            continue;
        }
        for (NSString *keyword in keywords) {
            if ([candidate rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matches addObject:keyword];
            }
        }
    }
    return matches.array;
}

- (NSDictionary *)controlDictionary:(UIControl *)control {
    NSMutableArray *targetClasses = [NSMutableArray array];
    NSMutableDictionary *actions = [NSMutableDictionary dictionary];
    NSArray<NSNumber *> *events = @[ @(UIControlEventTouchUpInside), @(UIControlEventValueChanged), @(UIControlEventEditingChanged), @(UIControlEventEditingDidEnd) ];
    for (id target in control.allTargets) {
        NSString *targetClass = NSStringFromClass([target class]) ?: @"";
        if (targetClass.length > 0) {
            [targetClasses addObject:targetClass];
        }
        for (NSNumber *event in events) {
            NSArray<NSString *> *selectors = [control actionsForTarget:target forControlEvent:event.unsignedIntegerValue];
            if (selectors.count > 0) {
                NSString *key = [NSString stringWithFormat:@"%@:%@", targetClass, event];
                actions[key] = selectors;
            }
        }
    }
    return @{
        @"enabled" : @(control.enabled),
        @"selected" : @(control.selected),
        @"highlighted" : @(control.highlighted),
        @"contentHorizontalAlignment" : @(control.contentHorizontalAlignment),
        @"contentVerticalAlignment" : @(control.contentVerticalAlignment),
        @"targetClasses" : targetClasses,
        @"actions" : actions,
    };
}

- (NSArray *)constraintDictionariesForView:(UIView *)view {
    NSMutableArray *constraints = [NSMutableArray array];
    NSUInteger maximum = 80;
    for (NSLayoutConstraint *constraint in view.constraints) {
        if (constraints.count >= maximum) {
            [constraints addObject:@{@"truncated" : @YES, @"remaining" : @(view.constraints.count - constraints.count)}];
            break;
        }
        id firstItem = constraint.firstItem;
        id secondItem = constraint.secondItem;
        [constraints addObject:@{
            @"firstItemClass" : firstItem ? NSStringFromClass([firstItem class]) : @"",
            @"firstAttribute" : @(constraint.firstAttribute),
            @"relation" : @(constraint.relation),
            @"secondItemClass" : secondItem ? NSStringFromClass([secondItem class]) : @"",
            @"secondAttribute" : @(constraint.secondAttribute),
            @"multiplier" : @(constraint.multiplier),
            @"constant" : @(constraint.constant),
            @"priority" : @(constraint.priority),
            @"active" : @(constraint.active),
            @"identifier" : constraint.identifier ?: @"",
        }];
    }
    return constraints;
}

- (NSArray *)gestureDictionariesForView:(UIView *)view {
    NSMutableArray *gestures = [NSMutableArray array];
    for (UIGestureRecognizer *gesture in view.gestureRecognizers ?: @[]) {
        [gestures addObject:@{
            @"class" : NSStringFromClass([gesture class]) ?: @"",
            @"address" : [NSString stringWithFormat:@"%p", gesture],
            @"enabled" : @(gesture.enabled),
            @"state" : @(gesture.state),
            @"cancelsTouchesInView" : @(gesture.cancelsTouchesInView),
            @"viewClass" : gesture.view ? NSStringFromClass([gesture.view class]) : @"",
        }];
    }
    return gestures;
}

- (NSArray *)responderChainForResponder:(UIResponder *)responder {
    NSMutableArray *chain = [NSMutableArray array];
    UIResponder *current = responder;
    for (NSUInteger index = 0; current && index < 24; index++) {
        [chain addObject:@{
            @"class" : NSStringFromClass([current class]) ?: @"",
            @"address" : [NSString stringWithFormat:@"%p", current],
        }];
        current = current.nextResponder;
    }
    return chain;
}

- (NSData *)screenshotDataForWindows:(NSArray<UIWindow *> *)windows {
    UIWindow *targetWindow = nil;
    for (UIWindow *window in windows) {
        if (window.isKeyWindow && !window.hidden && window.alpha > 0) {
            targetWindow = window;
            break;
        }
    }
    if (!targetWindow) {
        targetWindow = windows.firstObject;
    }
    if (!targetWindow || CGRectIsEmpty(targetWindow.bounds)) {
        return nil;
    }
    UIGraphicsBeginImageContextWithOptions(targetWindow.bounds.size, NO, targetWindow.screen.scale);
    BOOL success = [targetWindow drawViewHierarchyInRect:targetWindow.bounds afterScreenUpdates:NO];
    UIImage *image = success ? UIGraphicsGetImageFromCurrentImageContext() : nil;
    UIGraphicsEndImageContext();
    return image ? UIImagePNGRepresentation(image) : nil;
}

- (NSDictionary *)rectDictionary:(CGRect)rect {
    return @{@"x" : @(rect.origin.x), @"y" : @(rect.origin.y), @"width" : @(rect.size.width), @"height" : @(rect.size.height)};
}

- (NSDictionary *)edgeInsetsDictionary:(UIEdgeInsets)insets {
    return @{@"top" : @(insets.top), @"left" : @(insets.left), @"bottom" : @(insets.bottom), @"right" : @(insets.right)};
}

#pragma mark - Runtime snapshot

- (NSDictionary *)captureRuntimeForVisibleClassNames:(NSSet<NSString *> *)visibleClassNames {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        return @{@"included" : @YES, @"classCount" : @0};
    }
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);

    NSMutableArray<NSString *> *candidateNames = [NSMutableArray array];
    NSMutableDictionary<NSString *, id> *candidateClasses = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, id> *visibleClasses = [NSMutableDictionary dictionary];
    for (int index = 0; index < count; index++) {
        Class cls = classes[index];
        NSString *className = NSStringFromClass(cls) ?: @"";
        if ([visibleClassNames containsObject:className]) {
            visibleClasses[className] = cls;
        }
        if ([self isRuntimeCandidateClassName:className]) {
            if (candidateNames.count < kDYYYDiagnosticsMaximumRuntimeNames) {
                [candidateNames addObject:className];
                candidateClasses[className] = cls;
            }
        }
    }
    free(classes);
    [candidateNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSMutableOrderedSet<NSString *> *detailNames = [NSMutableOrderedSet orderedSet];
    for (NSString *name in [[visibleClasses allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        if ([self isProjectRuntimeClassName:name] || [self isRuntimeCandidateClassName:name]) {
            [detailNames addObject:name];
        }
    }
    for (NSString *name in candidateNames) {
        if (detailNames.count >= kDYYYDiagnosticsMaximumRuntimeDetails) {
            break;
        }
        if ([name rangeOfString:@"Comment" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"AI" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"Analysis" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"Segment" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"ABTest" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [detailNames addObject:name];
        }
    }

    NSMutableArray *details = [NSMutableArray array];
    for (NSString *name in detailNames) {
        Class cls = visibleClasses[name] ?: candidateClasses[name] ?: NSClassFromString(name);
        if (cls) {
            [details addObject:[self runtimeDictionaryForClass:cls]];
        }
    }

    return @{
        @"included" : @YES,
        @"totalLoadedClassCount" : @(count),
        @"candidateClassNames" : candidateNames,
        @"candidateNamesTruncated" : @(candidateNames.count >= kDYYYDiagnosticsMaximumRuntimeNames),
        @"classDetails" : details,
        @"detailsTruncated" : @(detailNames.count >= kDYYYDiagnosticsMaximumRuntimeDetails),
        @"loadedImages" : [self loadedImageNames],
    };
}

- (BOOL)isRuntimeCandidateClassName:(NSString *)className {
    if (className.length == 0) {
        return NO;
    }
    if ([self isProjectRuntimeClassName:className] && [className rangeOfString:@"AI"].location != NSNotFound) {
        return YES;
    }
    NSArray<NSString *> *keywords = @[ @"Comment", @"AIGC", @"Assistant", @"Copilot", @"Intelligence", @"Analysis", @"Explain", @"Insight", @"Summary", @"Segment", @"Tab", @"Panel", @"Header", @"ABTest", @"Experiment", @"FeatureGate" ];
    for (NSString *keyword in keywords) {
        if ([className rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isProjectRuntimeClassName:(NSString *)className {
    NSArray<NSString *> *prefixes = @[ @"AWE", @"AFD", @"IES", @"DUX", @"TT", @"BD", @"DYYY", @"_TtC" ];
    for (NSString *prefix in prefixes) {
        if ([className hasPrefix:prefix]) {
            return YES;
        }
    }
    return NO;
}

- (NSDictionary *)runtimeDictionaryForClass:(Class)cls {
    NSMutableArray *superclasses = [NSMutableArray array];
    Class current = cls;
    while (current && superclasses.count < 24) {
        [superclasses addObject:NSStringFromClass(current) ?: @""];
        current = class_getSuperclass(current);
    }
    return @{
        @"class" : NSStringFromClass(cls) ?: @"",
        @"image" : class_getImageName(cls) ? [NSString stringWithUTF8String:class_getImageName(cls)] : @"",
        @"superclasses" : superclasses,
        @"instanceSize" : @(class_getInstanceSize(cls)),
        @"methods" : [self methodsForClass:cls],
        @"classMethods" : [self methodsForClass:object_getClass(cls)],
        @"properties" : [self propertiesForClass:cls],
        @"ivars" : [self ivarsForClass:cls],
        @"protocols" : [self protocolsForClass:cls],
    };
}

- (NSArray *)methodsForClass:(Class)cls {
    if (!cls) {
        return @[];
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSUInteger limit = MIN((NSUInteger)count, 260);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:limit + 1];
    for (NSUInteger index = 0; index < limit; index++) {
        SEL selector = method_getName(methods[index]);
        const char *encoding = method_getTypeEncoding(methods[index]);
        [result addObject:@{
            @"selector" : selector ? NSStringFromSelector(selector) : @"",
            @"typeEncoding" : encoding ? [NSString stringWithUTF8String:encoding] : @"",
        }];
    }
    if (count > limit) {
        [result addObject:@{@"truncated" : @YES, @"remaining" : @(count - limit)}];
    }
    free(methods);
    return result;
}

- (NSArray *)propertiesForClass:(Class)cls {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    NSUInteger limit = MIN((NSUInteger)count, 180);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:limit + 1];
    for (NSUInteger index = 0; index < limit; index++) {
        const char *name = property_getName(properties[index]);
        const char *attributes = property_getAttributes(properties[index]);
        [result addObject:@{
            @"name" : name ? [NSString stringWithUTF8String:name] : @"",
            @"attributes" : attributes ? [NSString stringWithUTF8String:attributes] : @"",
        }];
    }
    if (count > limit) {
        [result addObject:@{@"truncated" : @YES, @"remaining" : @(count - limit)}];
    }
    free(properties);
    return result;
}

- (NSArray *)ivarsForClass:(Class)cls {
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    NSUInteger limit = MIN((NSUInteger)count, 180);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:limit + 1];
    for (NSUInteger index = 0; index < limit; index++) {
        const char *name = ivar_getName(ivars[index]);
        const char *type = ivar_getTypeEncoding(ivars[index]);
        [result addObject:@{
            @"name" : name ? [NSString stringWithUTF8String:name] : @"",
            @"typeEncoding" : type ? [NSString stringWithUTF8String:type] : @"",
            @"offset" : @(ivar_getOffset(ivars[index])),
        }];
    }
    if (count > limit) {
        [result addObject:@{@"truncated" : @YES, @"remaining" : @(count - limit)}];
    }
    free(ivars);
    return result;
}

- (NSArray *)protocolsForClass:(Class)cls {
    unsigned int count = 0;
    Protocol *__unsafe_unretained *protocols = class_copyProtocolList(cls, &count);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        const char *name = protocol_getName(protocols[index]);
        if (name) {
            [result addObject:[NSString stringWithUTF8String:name]];
        }
    }
    free(protocols);
    return result;
}

- (NSArray *)loadedImageNames {
    uint32_t count = _dyld_image_count();
    NSMutableArray *images = [NSMutableArray arrayWithCapacity:MIN(count, (uint32_t)2000)];
    for (uint32_t index = 0; index < count && images.count < 2000; index++) {
        const char *path = _dyld_get_image_name(index);
        if (!path) {
            continue;
        }
        NSString *fullPath = [NSString stringWithUTF8String:path];
        [images addObject:fullPath.lastPathComponent ?: fullPath];
    }
    return images;
}

#pragma mark - Serialization

- (NSArray<NSURL *> *)writeReport:(NSDictionary *)report
                   screenshotData:(NSData *)screenshotData
                          profile:(DYYYDiagnosticsProfile)profile
                            error:(NSError **)error {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd_HHmmss_SSS";
    NSString *profileName = profile == DYYYDiagnosticsProfileCommentPanel ? @"comment" : @"general";
    NSString *baseName = [NSString stringWithFormat:@"DYYY_Diagnostics_%@_%@", profileName, [formatter stringFromDate:[NSDate date]]];
    NSURL *directoryURL = [DYYYDiagnosticsCollector reportsDirectoryURL];
    NSURL *jsonURL = [directoryURL URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"json"]];
    NSURL *textURL = [directoryURL URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"txt"]];

    NSData *jsonData = nil;
    @try {
        id safeReport = [self JSONSafeObject:report];
        jsonData = [NSJSONSerialization dataWithJSONObject:safeReport options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:kDYYYDiagnosticsErrorDomain
                                         code:2
                                     userInfo:@{
                                         NSLocalizedDescriptionKey : @"诊断报告序列化失败",
                                         @"exceptionName" : exception.name ?: @"",
                                         @"exceptionReason" : exception.reason ?: @"",
                                     }];
        }
        return @[];
    }
    if (!jsonData || ![jsonData writeToURL:jsonURL options:NSDataWritingAtomic error:error]) {
        return @[];
    }
    NSString *summary = [self textSummaryForReport:report];
    if (![summary writeToURL:textURL atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        [[NSFileManager defaultManager] removeItemAtURL:jsonURL error:nil];
        return @[];
    }

    NSMutableArray<NSURL *> *files = [NSMutableArray arrayWithObjects:jsonURL, textURL, nil];
    if (screenshotData.length > 0) {
        NSURL *screenshotURL = [directoryURL URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"png"]];
        if ([screenshotData writeToURL:screenshotURL options:NSDataWritingAtomic error:error]) {
            [files addObject:screenshotURL];
        } else {
            [[NSFileManager defaultManager] removeItemAtURL:jsonURL error:nil];
            [[NSFileManager defaultManager] removeItemAtURL:textURL error:nil];
            return @[];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:baseName forKey:kDYYYDiagnosticsLatestBaseNameKey];
    return files;
}

- (id)JSONSafeObject:(id)object {
    if (!object || object == [NSNull null]) {
        return [NSNull null];
    }
    if ([object isKindOfClass:[NSString class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)object) == CFBooleanGetTypeID()) {
            return object;
        }
        double value = [object doubleValue];
        if (isnan(value)) {
            return @"NaN";
        }
        if (isinf(value)) {
            return value > 0 ? @"+Infinity" : @"-Infinity";
        }
        return object;
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:[(NSArray *)object count]];
        for (id value in (NSArray *)object) {
            [result addObject:[self JSONSafeObject:value]];
        }
        return result;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)object count]];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
          NSString *safeKey = [key isKindOfClass:[NSString class]] ? key : [key description];
          result[safeKey ?: @"<unknown-key>"] = [self JSONSafeObject:value];
        }];
        return result;
    }
    if ([object isKindOfClass:[NSSet class]]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:[(NSSet *)object count]];
        for (id value in (NSSet *)object) {
            [result addObject:[self JSONSafeObject:value]];
        }
        return result;
    }
    if ([object isKindOfClass:[NSURL class]]) {
        return [(NSURL *)object absoluteString] ?: @"";
    }
    if ([object isKindOfClass:[NSDate class]]) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        return [formatter stringFromDate:object] ?: @"";
    }
    return @{
        @"unsupportedType" : NSStringFromClass([object class]) ?: @"",
        @"descriptionRedacted" : @YES,
    };
}

- (NSString *)textSummaryForReport:(NSDictionary *)report {
    NSDictionary *metadata = report[@"metadata"];
    NSDictionary *ui = report[@"ui"];
    NSDictionary *runtime = report[@"runtime"];
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"DYYY Diagnostics\n================\nTimestamp: %@\nProfile: %@\nSource: %@\nPlugin: %@\nApp: %@ (%@)\niOS: %@\nDevice: %@\n\n",
                       metadata[@"timestamp"] ?: @"",
                       metadata[@"profile"] ?: @"",
                       metadata[@"sourceBaseline"] ?: @"",
                       metadata[@"pluginVersion"] ?: @"",
                       metadata[@"app"][@"version"] ?: @"",
                       metadata[@"app"][@"build"] ?: @"",
                       metadata[@"device"][@"systemVersion"] ?: @"",
                       metadata[@"device"][@"hardware"] ?: @""];
    [text appendFormat:@"Privacy: %@\n\n", metadata[@"privacy"] ?: @{}];
    [text appendFormat:@"View nodes: %@\nCandidates: %lu\n\n", ui[@"nodeCount"] ?: @0, (unsigned long)[ui[@"candidates"] count]];
    [text appendString:@"UI candidates\n-------------\n"];
    for (NSDictionary *candidate in ui[@"candidates"] ?: @[]) {
        [text appendFormat:@"%@\n  %@\n  matches=%@\n  responder=%@\n",
                           candidate[@"class"] ?: @"",
                           candidate[@"path"] ?: @"",
                           candidate[@"keywordMatches"] ?: @[],
                           [candidate[@"responderChain"] valueForKey:@"class"] ?: @[]];
    }
    NSArray *runtimeNames = runtime[@"candidateClassNames"] ?: @[];
    [text appendFormat:@"\nRuntime candidate classes: %lu\n-------------------------\n", (unsigned long)runtimeNames.count];
    NSUInteger maximum = MIN(runtimeNames.count, (NSUInteger)1200);
    for (NSUInteger index = 0; index < maximum; index++) {
        [text appendFormat:@"%@\n", runtimeNames[index]];
    }
    if (runtimeNames.count > maximum) {
        [text appendFormat:@"... %lu more classes in JSON report\n", (unsigned long)(runtimeNames.count - maximum)];
    }
    return text;
}

@end
