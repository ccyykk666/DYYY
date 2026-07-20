#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^DYYYNativeTabBarSelectionHandler)(UITabBar *tabBar, UITabBarItem *item);

@interface DYYYNativeTabBarDelegateProxy : NSObject <UITabBarDelegate>

@property(nonatomic, weak, nullable) id<UITabBarDelegate> forwardingDelegate;
@property(nonatomic, copy, nullable) DYYYNativeTabBarSelectionHandler selectionHandler;

@end

NS_ASSUME_NONNULL_END
