#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DYYYDiagnosticsProfile) {
    DYYYDiagnosticsProfileGeneral = 0,
    DYYYDiagnosticsProfileCommentPanel = 1,
};

FOUNDATION_EXPORT NSString *const DYYYDiagnosticsGestureEnabledKey;
FOUNDATION_EXPORT NSString *const DYYYDiagnosticsGestureProfileKey;
FOUNDATION_EXPORT NSString *const DYYYDiagnosticsIncludeTextKey;
FOUNDATION_EXPORT NSString *const DYYYDiagnosticsIncludeScreenshotKey;
FOUNDATION_EXPORT NSString *const DYYYDiagnosticsIncludeConstraintsKey;
FOUNDATION_EXPORT NSString *const DYYYDiagnosticsIncludeRuntimeKey;

typedef void (^DYYYDiagnosticsCompletion)(NSArray<NSURL *> *_Nullable fileURLs, NSError *_Nullable error);

/**
 * 可复用的运行时诊断采集器。
 *
 * UI 层只负责触发采集与导出；视图树、控制器、运行时类和环境信息均在此集中处理。
 * 默认对界面文字脱敏，不采集 Cookie、账号凭据或非 DYYY 的偏好值。
 */
@interface DYYYDiagnosticsCollector : NSObject

+ (instancetype)sharedCollector;

+ (BOOL)captureGestureEnabled;
+ (void)setCaptureGestureEnabled:(BOOL)enabled;
+ (DYYYDiagnosticsProfile)captureGestureProfile;
+ (void)setCaptureGestureProfile:(DYYYDiagnosticsProfile)profile;

+ (BOOL)includeVisibleText;
+ (void)setIncludeVisibleText:(BOOL)enabled;
+ (BOOL)includeScreenshot;
+ (void)setIncludeScreenshot:(BOOL)enabled;
+ (BOOL)includeConstraints;
+ (void)setIncludeConstraints:(BOOL)enabled;
+ (BOOL)includeRuntimeDetails;
+ (void)setIncludeRuntimeDetails:(BOOL)enabled;

/**
 * 给普通应用窗口安装或移除三指长按诊断手势。可重复调用。
 */
+ (void)syncCaptureGestureForWindow:(UIWindow *)window;
+ (void)syncCaptureGestureForAllWindows;

/**
 * 采集当前页面。UI 数据在主线程读取，运行时整理和文件写入在后台队列完成。
 */
- (void)collectCurrentStateWithProfile:(DYYYDiagnosticsProfile)profile completion:(nullable DYYYDiagnosticsCompletion)completion;

+ (NSURL *)reportsDirectoryURL;
+ (NSArray<NSURL *> *)latestReportFileURLs;
+ (NSUInteger)reportCount;
+ (unsigned long long)reportsSize;
+ (BOOL)clearReports:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
