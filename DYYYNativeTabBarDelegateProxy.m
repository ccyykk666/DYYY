#import "DYYYNativeTabBarDelegateProxy.h"

@implementation DYYYNativeTabBarDelegateProxy

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    if (self.selectionHandler) {
        self.selectionHandler(tabBar, item);
        return;
    }

    id<UITabBarDelegate> delegate = self.forwardingDelegate;
    if ([delegate respondsToSelector:_cmd]) {
        [delegate tabBar:tabBar didSelectItem:item];
    }
}

- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.forwardingDelegate respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
    if ([self.forwardingDelegate respondsToSelector:selector]) {
        return self.forwardingDelegate;
    }
    return [super forwardingTargetForSelector:selector];
}

@end
