#import <UIKit/UIKit.h>

@class AWENormalModeTabBar;
@class AWENormalModeTabBarGeneralButton;

@interface DYYYSystemTabBarDelegate : NSObject <UITabBarDelegate>

@property(nonatomic, weak) AWENormalModeTabBar *sourceTabBar;
@property(nonatomic, weak) id<UITabBarDelegate> originalDelegate;
@property(nonatomic, copy) NSArray<AWENormalModeTabBarGeneralButton *> *sourceButtons;

@end
