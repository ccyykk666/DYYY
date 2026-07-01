#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 评论区 AI 解析适配器。
 *
 * 在评论 Tab 数据源生成阶段移除 AI 解析模型，其余界面与布局保持抖音原生行为。
 */
@interface DYYYCommentAIBlocker : NSObject

+ (BOOL)isEnabled;
+ (NSArray *)filteredTabItems:(NSArray *)items;

+ (void)markTabContentController:(UIViewController *)viewController;
+ (BOOL)isManagedTabContentController:(UIViewController *)viewController;
+ (BOOL)shouldManageTabContentController:(UIViewController *)viewController delegate:(nullable id)delegate;

+ (void)recordTabConfiguration:(nullable id)configuration;
+ (void)recordTabItems:(nullable NSArray *)items;
+ (void)recordTabModel:(nullable id)model index:(NSInteger)index viewController:(nullable UIViewController *)viewController;
+ (NSDictionary *)diagnosticsSnapshot;

@end

NS_ASSUME_NONNULL_END
