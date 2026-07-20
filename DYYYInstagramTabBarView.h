#import <UIKit/UIKit.h>

@interface DYYYInstagramTabBarView : UIView

@property(nonatomic, copy) void (^selectionHandler)(NSUInteger index);
@property(nonatomic, assign, readonly) NSUInteger selectedIndex;

- (void)configureWithNormalImages:(NSArray<UIImage *> *)normalImages
                   selectedImages:(NSArray<UIImage *> *)selectedImages
              accessibilityLabels:(NSArray<NSString *> *)accessibilityLabels
                    selectedIndex:(NSUInteger)selectedIndex;
- (void)setSelectedIndex:(NSUInteger)selectedIndex animated:(BOOL)animated;
- (void)refreshAppearance;

@end
