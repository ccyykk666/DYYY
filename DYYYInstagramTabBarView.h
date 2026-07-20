#import <UIKit/UIKit.h>

@interface DYYYInstagramTabBarView : UIView

@property(nonatomic, copy) void (^selectionHandler)(NSUInteger index);
@property(nonatomic, assign, readonly) NSUInteger selectedIndex;
@property(nonatomic, assign, getter=isDarkAppearance) BOOL darkAppearance;

- (void)configureWithNormalImages:(NSArray<UIImage *> *)normalImages
                   selectedImages:(NSArray<UIImage *> *)selectedImages
              accessibilityLabels:(NSArray<NSString *> *)accessibilityLabels
                    selectedIndex:(NSUInteger)selectedIndex;
- (void)setSelectedIndex:(NSUInteger)selectedIndex animated:(BOOL)animated;
- (void)refreshAppearance;

@end
