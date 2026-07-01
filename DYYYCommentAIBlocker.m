#import "DYYYCommentAIBlocker.h"

#import <objc/runtime.h>

#import "AwemeHeaders.h"

static char kDYYYManagedCommentTabControllerKey;
static char kDYYYCommentAIBlockerLayoutAppliedKey;

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
            view.hidden = NO;
            view.alpha = 1.0;
            for (UIView *subview in view.subviews) {
                subview.hidden = NO;
                subview.alpha = 1.0;
            }
        } else if ([className containsString:@"CommentPanelHeaderNewCell"]) {
            for (UIView *subview in view.subviews) {
                subview.hidden = YES;
            }
            view.userInteractionEnabled = NO;
        } else if ([className isEqualToString:@"IESSegmentedControl"]) {
            view.hidden = YES;
            view.alpha = 0.0;
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
        [self markTabContentController:tabController];
        [tabController setCurrentIndex:0];
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
    }
    [rootView setNeedsLayout];
}

@end
