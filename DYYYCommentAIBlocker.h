#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 评论区 AI 解析适配器。
 *
 * 负责将评论区双 Tab 收敛为原生评论单页，并阻止 AI 页被选择或创建。
 */
@interface DYYYCommentAIBlocker : NSObject

+ (BOOL)isEnabled;
+ (NSArray *)filteredTabItems:(NSArray *)items;
+ (BOOL)shouldBlockViewController:(nullable UIViewController *)viewController;
+ (void)applyToContainerController:(UIViewController *)containerController;

+ (void)markTabContentController:(UIViewController *)viewController;
+ (BOOL)isManagedTabContentController:(UIViewController *)viewController;
+ (BOOL)shouldManageTabContentController:(UIViewController *)viewController delegate:(nullable id)delegate;

+ (void)recordTabConfiguration:(nullable id)configuration;
+ (void)recordTabItems:(nullable NSArray *)items;
+ (void)recordTabModel:(nullable id)model index:(NSInteger)index viewController:(nullable UIViewController *)viewController;
+ (NSDictionary *)diagnosticsSnapshot;

@end

NS_ASSUME_NONNULL_END
