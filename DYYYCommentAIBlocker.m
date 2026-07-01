#import "DYYYCommentAIBlocker.h"

#import <objc/runtime.h>

#import "AwemeHeaders.h"

static char kDYYYManagedCommentTabControllerKey;
static char kDYYYCommentAIBlockerLayoutAppliedKey;
static char kDYYYCommentAIBlockerApplyingKey;
static NSDictionary *dyyyLatestCommentTabConfigurationSnapshot;
static NSDictionary *dyyyLatestCommentTabItemsSnapshot;
static NSMutableArray<NSDictionary *> *dyyyLatestCommentTabModelSnapshots;

static BOOL DYYYCommentAIProbePropertyIsRelevant(NSString *name) {
    if (name.length == 0) {
        return NO;
    }
    NSArray<NSString *> *keywords = @[
        @"tab", @"title", @"type", @"name", @"identifier", @"enable", @"show",
        @"style", @"index", @"config", @"item", @"model", @"scene", @"source"
    ];
    NSString *lowercaseName = name.lowercaseString;
    for (NSString *keyword in keywords) {
        if ([lowercaseName containsString:keyword]) {
            return YES;
        }
    }
    return NO;
}

static id DYYYCommentAIProbeSnapshotObject(id object, NSUInteger depth);

static id DYYYCommentAIProbeSnapshotCollection(id collection, NSUInteger depth) {
    if ([collection isKindOfClass:[NSArray class]]) {
        NSArray *array = collection;
        NSMutableArray *items = [NSMutableArray array];
        NSUInteger count = MIN(array.count, (NSUInteger)8);
        for (NSUInteger index = 0; index < count; index++) {
            [items addObject:DYYYCommentAIProbeSnapshotObject(array[index], depth + 1) ?: [NSNull null]];
        }
        return @{
            @"kind" : @"array",
            @"class" : NSStringFromClass([collection class]) ?: @"",
            @"count" : @(array.count),
            @"items" : items,
        };
    }

    NSDictionary *dictionary = collection;
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (id key in dictionary.allKeys) {
        if ([key isKindOfClass:[NSString class]]) {
            [keys addObject:key];
        }
    }
    [keys sortUsingSelector:@selector(compare:)];

    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSUInteger count = MIN(keys.count, (NSUInteger)20);
    for (NSUInteger index = 0; index < count; index++) {
        NSString *key = keys[index];
        if (!DYYYCommentAIProbePropertyIsRelevant(key)) {
            continue;
        }
        values[key] = DYYYCommentAIProbeSnapshotObject(dictionary[key], depth + 1) ?: [NSNull null];
    }
    return @{
        @"kind" : @"dictionary",
        @"class" : NSStringFromClass([collection class]) ?: @"",
        @"count" : @(dictionary.count),
        @"keys" : [keys subarrayWithRange:NSMakeRange(0, count)],
        @"relevantValues" : values,
    };
}

static id DYYYCommentAIProbeSnapshotObject(id object, NSUInteger depth) {
    if (!object) {
        return [NSNull null];
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSString class]]) {
        NSString *value = object;
        return value.length > 120 ? [[value substringToIndex:120] stringByAppendingString:@"…"] : value;
    }
    if (object_isClass(object)) {
        return @{@"kind" : @"class", @"name" : NSStringFromClass(object) ?: @""};
    }
    if (depth >= 3) {
        return @{@"class" : NSStringFromClass([object class]) ?: @"", @"truncated" : @YES};
    }
    if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSDictionary class]]) {
        return DYYYCommentAIProbeSnapshotCollection(object, depth);
    }

    NSMutableDictionary *snapshot = [@{
        @"kind" : @"object",
        @"class" : NSStringFromClass([object class]) ?: @"",
    } mutableCopy];
    NSMutableArray<NSString *> *propertyNames = [NSMutableArray array];
    NSMutableDictionary *propertyValues = [NSMutableDictionary dictionary];

    Class currentClass = [object class];
    for (NSUInteger classDepth = 0; currentClass && classDepth < 5; classDepth++, currentClass = class_getSuperclass(currentClass)) {
        unsigned int propertyCount = 0;
        objc_property_t *properties = class_copyPropertyList(currentClass, &propertyCount);
        for (unsigned int index = 0; index < propertyCount; index++) {
            const char *rawName = property_getName(properties[index]);
            NSString *name = rawName ? [NSString stringWithUTF8String:rawName] : nil;
            if (name.length == 0 || [propertyNames containsObject:name]) {
                continue;
            }
            [propertyNames addObject:name];
            if (!DYYYCommentAIProbePropertyIsRelevant(name) || propertyValues.count >= 24) {
                continue;
            }
            @try {
                id value = [object valueForKey:name];
                propertyValues[name] = DYYYCommentAIProbeSnapshotObject(value, depth + 1) ?: [NSNull null];
            } @catch (__unused NSException *exception) {
                propertyValues[name] = @{@"readFailed" : @YES};
            }
        }
        free(properties);
    }

    snapshot[@"properties"] = propertyNames;
    snapshot[@"relevantValues"] = propertyValues;
    return snapshot;
}

@implementation DYYYCommentAIBlocker

#pragma mark - Configuration

+ (BOOL)isEnabled {
    return DYYYGetBool(@"DYYYBlockCommentAIParse");
}

+ (NSArray *)filteredTabItems:(NSArray *)items {
    if (![self isEnabled] || items.count <= 1) {
        return items ?: @[];
    }
    return @[ items.firstObject ];
}

+ (BOOL)shouldBlockViewController:(UIViewController *)viewController {
    if (![self isEnabled] || !viewController) {
        return NO;
    }
    NSString *className = NSStringFromClass([viewController class]) ?: @"";
    return [className rangeOfString:@"CommentAIParse" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [className rangeOfString:@"AIParseViewController" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

#pragma mark - Tab ownership

+ (void)markTabContentController:(UIViewController *)viewController {
    if (!viewController) {
        return;
    }
    objc_setAssociatedObject(viewController, &kDYYYManagedCommentTabControllerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (BOOL)isManagedTabContentController:(UIViewController *)viewController {
    return [self isEnabled] && [objc_getAssociatedObject(viewController, &kDYYYManagedCommentTabControllerKey) boolValue];
}

#pragma mark - Diagnostics

+ (void)recordTabConfiguration:(id)configuration {
    NSDictionary *snapshot = DYYYCommentAIProbeSnapshotObject(configuration, 0);
    @synchronized(self) {
        dyyyLatestCommentTabConfigurationSnapshot = snapshot;
    }
}

+ (void)recordTabItems:(NSArray *)items {
    NSDictionary *snapshot = DYYYCommentAIProbeSnapshotObject(items, 0);
    @synchronized(self) {
        dyyyLatestCommentTabItemsSnapshot = snapshot;
    }
}

+ (void)recordTabModel:(id)model index:(NSInteger)index viewController:(UIViewController *)viewController {
    NSDictionary *snapshot = @{
        @"index" : @(index),
        @"model" : DYYYCommentAIProbeSnapshotObject(model, 0) ?: [NSNull null],
        @"viewControllerClass" : viewController ? NSStringFromClass([viewController class]) ?: @"" : [NSNull null],
    };
    @synchronized(self) {
        if (!dyyyLatestCommentTabModelSnapshots) {
            dyyyLatestCommentTabModelSnapshots = [NSMutableArray array];
        }
        [dyyyLatestCommentTabModelSnapshots addObject:snapshot];
        if (dyyyLatestCommentTabModelSnapshots.count > 8) {
            [dyyyLatestCommentTabModelSnapshots removeObjectAtIndex:0];
        }
    }
}

+ (NSDictionary *)diagnosticsSnapshot {
    @synchronized(self) {
        return @{
            @"configuration" : dyyyLatestCommentTabConfigurationSnapshot ?: [NSNull null],
            @"segmentedItems" : dyyyLatestCommentTabItemsSnapshot ?: [NSNull null],
            @"modelMappings" : [dyyyLatestCommentTabModelSnapshots copy] ?: @[],
        };
    }
}

#pragma mark - Layout

+ (void)applyToContainerController:(UIViewController *)containerController {
    if (![self isEnabled] || !containerController) {
        return;
    }
    if (![NSThread isMainThread]) {
        __weak UIViewController *weakController = containerController;
        dispatch_async(dispatch_get_main_queue(), ^{
          [self applyToContainerController:weakController];
        });
        return;
    }

    UIView *rootView = containerController.viewIfLoaded;
    if (!rootView) {
        return;
    }
    if ([objc_getAssociatedObject(containerController, &kDYYYCommentAIBlockerApplyingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(containerController, &kDYYYCommentAIBlockerApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {
        BOOL firstApplication = ![objc_getAssociatedObject(containerController, &kDYYYCommentAIBlockerLayoutAppliedKey) boolValue];
        objc_setAssociatedObject(containerController, &kDYYYCommentAIBlockerLayoutAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        NSMutableArray<UIView *> *pendingViews = [NSMutableArray arrayWithObject:rootView];
        NSMutableOrderedSet<AWETabContentViewController *> *tabControllers = [NSMutableOrderedSet orderedSet];
        UICollectionView *outerCollectionView = nil;

        while (pendingViews.count > 0) {
            UIView *view = pendingViews.lastObject;
            [pendingViews removeLastObject];
            [pendingViews addObjectsFromArray:view.subviews ?: @[]];

            NSString *className = NSStringFromClass([view class]) ?: @"";
            if ([className containsString:@"CommentVCHeaderCloseBar"]) {
                if (view.hidden) {
                    view.hidden = NO;
                }
                if (view.alpha != 1.0) {
                    view.alpha = 1.0;
                }
                for (UIView *subview in view.subviews) {
                    if (subview.hidden) {
                        subview.hidden = NO;
                    }
                    if (subview.alpha != 1.0) {
                        subview.alpha = 1.0;
                    }
                }
            } else if ([className containsString:@"CommentPanelHeaderNewCell"]) {
                for (UIView *subview in view.subviews) {
                    if (!subview.hidden) {
                        subview.hidden = YES;
                    }
                }
                view.userInteractionEnabled = NO;
            } else if ([className isEqualToString:@"IESSegmentedControl"]) {
                if (!view.hidden) {
                    view.hidden = YES;
                }
                if (view.alpha != 0.0) {
                    view.alpha = 0.0;
                }
                view.userInteractionEnabled = NO;
            }

            if (!outerCollectionView && [view isKindOfClass:[UICollectionView class]] && view.superview == rootView) {
                outerCollectionView = (UICollectionView *)view;
            }

            if ([className isEqualToString:@"AWETabContentItemContainerCell"]) {
                UIResponder *responder = view;
                for (NSUInteger index = 0; responder && index < 20; index++) {
                    if ([responder isKindOfClass:NSClassFromString(@"AWETabContentViewController")]) {
                        [tabControllers addObject:(AWETabContentViewController *)responder];
                        break;
                    }
                    responder = responder.nextResponder;
                }
            }
        }

        for (AWETabContentViewController *tabController in tabControllers) {
            BOOL wasManaged = [self isManagedTabContentController:tabController];
            if (!wasManaged) {
                [self markTabContentController:tabController];
                [tabController setCurrentIndex:0];
            }
            UICollectionView *contentScrollView = tabController.contentScrollView;
            contentScrollView.scrollEnabled = NO;
            contentScrollView.bounces = NO;

            if (!wasManaged) {
                dispatch_async(dispatch_get_main_queue(), ^{
                  if (![self isEnabled] || ![self isManagedTabContentController:tabController]) {
                      return;
                  }
                  [tabController reloadTabContentWithCount:1];
                  [tabController updateSelectedIndex:0 animated:NO];
                });
            }
        }

        if (firstApplication && outerCollectionView) {
            [outerCollectionView.collectionViewLayout invalidateLayout];
            [outerCollectionView setNeedsLayout];
            [rootView setNeedsLayout];
        }
    } @finally {
        objc_setAssociatedObject(containerController, &kDYYYCommentAIBlockerApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

@end
