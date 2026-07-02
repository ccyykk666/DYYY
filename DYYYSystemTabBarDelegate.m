#import "DYYYSystemTabBarDelegate.h"

#import <objc/message.h>

#import "AwemeHeaders.h"

@implementation DYYYSystemTabBarDelegate

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    if ([self.originalDelegate respondsToSelector:@selector(tabBar:didSelectItem:)]) {
        [self.originalDelegate tabBar:tabBar didSelectItem:item];
    }

    NSUInteger index = [tabBar.items indexOfObjectIdenticalTo:item];
    if (index == NSNotFound || index >= self.sourceButtons.count) {
        return;
    }

    AWENormalModeTabBarGeneralButton *button = self.sourceButtons[index];
    if (!button.userInteractionEnabled) {
        return;
    }

    id buttonDelegate = button.delegate;
    SEL tapSelector = NSSelectorFromString(@"tabBarButtonDidTouchUpInside:gestureRecognizer:");
    if ([buttonDelegate respondsToSelector:tapSelector]) {
        id gestureRecognizer = nil;
        SEL gestureSelector = NSSelectorFromString(@"singleTapGes");
        if ([button respondsToSelector:gestureSelector]) {
            gestureRecognizer = ((id (*)(id, SEL))objc_msgSend)(button, gestureSelector);
        }
        ((void (*)(id, SEL, id, id))objc_msgSend)(buttonDelegate, tapSelector, button, gestureRecognizer);
        return;
    }

    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [super respondsToSelector:aSelector] || [self.originalDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.originalDelegate respondsToSelector:aSelector]) {
        return self.originalDelegate;
    }
    return [super forwardingTargetForSelector:aSelector];
}

@end
