#import "DYYYCommentAIBlocker.h"

#import <objc/runtime.h>

#import "AwemeHeaders.h"

static char kDYYYManagedCommentTabControllerKey;
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

    NSMutableArray *filteredItems = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        if ([item isKindOfClass:[NSString class]]) {
            NSString *title = item;
            if ([title rangeOfString:@"AI 解析" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [title rangeOfString:@"AI解析" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                continue;
            }
        }
        [filteredItems addObject:item];
    }
    return filteredItems.count > 0 && filteredItems.count < items.count ? filteredItems : items;
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

+ (BOOL)shouldManageTabContentController:(UIViewController *)viewController delegate:(id)delegate {
    if (![self isEnabled] || !viewController) {
        return NO;
    }
    if ([self isManagedTabContentController:viewController]) {
        return YES;
    }

    id resolvedDelegate = delegate;
    if (!resolvedDelegate) {
        @try {
            resolvedDelegate = [viewController valueForKey:@"delegate"];
        } @catch (__unused NSException *exception) {
            resolvedDelegate = nil;
        }
    }

    NSString *delegateClassName = resolvedDelegate ? NSStringFromClass([resolvedDelegate class]) ?: @"" : @"";
    if ([delegateClassName containsString:@"CommentContainerInnerViewController"]) {
        [self markTabContentController:viewController];
        return YES;
    }
    return NO;
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

@end
