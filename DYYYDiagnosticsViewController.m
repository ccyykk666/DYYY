#import "DYYYDiagnosticsViewController.h"

#import "DYYYBottomAlertView.h"
#import "DYYYDiagnostics.h"
#import "DYYYUtils.h"

typedef NS_ENUM(NSInteger, DYYYDiagnosticsSection) {
    DYYYDiagnosticsSectionOverview = 0,
    DYYYDiagnosticsSectionCapture,
    DYYYDiagnosticsSectionPrivacy,
    DYYYDiagnosticsSectionReports,
    DYYYDiagnosticsSectionCount,
};

typedef NS_ENUM(NSInteger, DYYYDiagnosticsCaptureRow) {
    DYYYDiagnosticsCaptureRowGesture = 0,
    DYYYDiagnosticsCaptureRowProfile,
    DYYYDiagnosticsCaptureRowGeneralNow,
    DYYYDiagnosticsCaptureRowCommentNow,
    DYYYDiagnosticsCaptureRowCount,
};

typedef NS_ENUM(NSInteger, DYYYDiagnosticsPrivacyRow) {
    DYYYDiagnosticsPrivacyRowText = 0,
    DYYYDiagnosticsPrivacyRowScreenshot,
    DYYYDiagnosticsPrivacyRowConstraints,
    DYYYDiagnosticsPrivacyRowRuntime,
    DYYYDiagnosticsPrivacyRowCount,
};

typedef NS_ENUM(NSInteger, DYYYDiagnosticsReportsRow) {
    DYYYDiagnosticsReportsRowSummary = 0,
    DYYYDiagnosticsReportsRowShareLatest,
    DYYYDiagnosticsReportsRowClear,
    DYYYDiagnosticsReportsRowCount,
};

@interface DYYYDiagnosticsViewController ()

@property(nonatomic, assign) BOOL collecting;

@end

@implementation DYYYDiagnosticsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DYYY 诊断工具";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController.presentingViewController && self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                              target:self
                                                                                              action:@selector(close)];
    }
    [self.tableView reloadData];
}

- (void)close {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return DYYYDiagnosticsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case DYYYDiagnosticsSectionOverview:
            return 1;
        case DYYYDiagnosticsSectionCapture:
            return DYYYDiagnosticsCaptureRowCount;
        case DYYYDiagnosticsSectionPrivacy:
            return DYYYDiagnosticsPrivacyRowCount;
        case DYYYDiagnosticsSectionReports:
            return DYYYDiagnosticsReportsRowCount;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case DYYYDiagnosticsSectionOverview:
            return @"说明";
        case DYYYDiagnosticsSectionCapture:
            return @"采集";
        case DYYYDiagnosticsSectionPrivacy:
            return @"内容与隐私";
        case DYYYDiagnosticsSectionReports:
            return @"报告";
        default:
            return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case DYYYDiagnosticsSectionCapture:
            return @"建议开启四指长按，返回目标页面后用四根手指长按约 1 秒。采集完成后再回到这里分享最新报告。";
        case DYYYDiagnosticsSectionPrivacy:
            return @"默认不保存昵称、评论正文、输入内容或截图。诊断报告不会读取 Cookie、账号凭据和非 DYYY 的偏好值。";
        case DYYYDiagnosticsSectionReports:
            return @"JSON 用于完整分析，TXT 用于快速定位；若开启截图，还会生成 PNG。";
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == DYYYDiagnosticsSectionOverview) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = @"只记录，不修改抖音行为";
        cell.detailTextLabel.text = @"采集当前窗口、控制器、视图树、约束、响应链及相关运行时类。评论区专项会重点标记 AI、解析、评论、标签页和面板结构。";
        cell.detailTextLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.section == DYYYDiagnosticsSectionCapture) {
        return [self captureCellForRow:indexPath.row];
    }
    if (indexPath.section == DYYYDiagnosticsSectionPrivacy) {
        return [self privacyCellForRow:indexPath.row];
    }
    return [self reportsCellForRow:indexPath.row];
}

- (UITableViewCell *)captureCellForRow:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (row == DYYYDiagnosticsCaptureRowGesture) {
        cell.textLabel.text = @"启用四指长按采集";
        cell.detailTextLabel.text = @"在任意普通页面原地采集";
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = [DYYYDiagnosticsCollector captureGestureEnabled];
        toggle.accessibilityIdentifier = DYYYDiagnosticsGestureEnabledKey;
        [toggle addTarget:self action:@selector(optionSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row == DYYYDiagnosticsCaptureRowProfile) {
        cell.textLabel.text = @"四指采集模式";
        UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[ @"通用", @"评论区专项" ]];
        control.selectedSegmentIndex = [DYYYDiagnosticsCollector captureGestureProfile];
        [control addTarget:self action:@selector(profileChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = control;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row == DYYYDiagnosticsCaptureRowGeneralNow) {
        cell.textLabel.text = @"立即采集当前界面（通用）";
        cell.detailTextLabel.text = @"用于验证诊断工具或排查其他页面";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"立即采集当前界面（评论区专项）";
        cell.detailTextLabel.text = @"若当前不是评论区，建议改用四指手势";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (UITableViewCell *)privacyCellForRow:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UISwitch *toggle = [[UISwitch alloc] init];
    NSString *key = nil;
    if (row == DYYYDiagnosticsPrivacyRowText) {
        cell.textLabel.text = @"包含可见界面文字";
        cell.detailTextLabel.text = @"可能包含昵称、评论正文和输入内容";
        key = DYYYDiagnosticsIncludeTextKey;
        toggle.on = [DYYYDiagnosticsCollector includeVisibleText];
    } else if (row == DYYYDiagnosticsPrivacyRowScreenshot) {
        cell.textLabel.text = @"附带当前页面截图";
        cell.detailTextLabel.text = @"可能包含头像、昵称和评论内容";
        key = DYYYDiagnosticsIncludeScreenshotKey;
        toggle.on = [DYYYDiagnosticsCollector includeScreenshot];
    } else if (row == DYYYDiagnosticsPrivacyRowConstraints) {
        cell.textLabel.text = @"包含布局约束";
        cell.detailTextLabel.text = @"用于恢复控件位置和标题布局";
        key = DYYYDiagnosticsIncludeConstraintsKey;
        toggle.on = [DYYYDiagnosticsCollector includeConstraints];
    } else {
        cell.textLabel.text = @"包含运行时类详情";
        cell.detailTextLabel.text = @"记录相关类的方法、属性、成员变量和协议";
        key = DYYYDiagnosticsIncludeRuntimeKey;
        toggle.on = [DYYYDiagnosticsCollector includeRuntimeDetails];
    }
    toggle.accessibilityIdentifier = key;
    [toggle addTarget:self action:@selector(optionSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)reportsCellForRow:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (row == DYYYDiagnosticsReportsRowSummary) {
        cell.textLabel.text = @"已保存报告";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 份 · %@", (unsigned long)[DYYYDiagnosticsCollector reportCount],
                                                               [DYYYUtils formattedSize:[DYYYDiagnosticsCollector reportsSize]]];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row == DYYYDiagnosticsReportsRowShareLatest) {
        cell.textLabel.text = @"分享最新报告";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"清除全部诊断报告";
        cell.textLabel.textColor = [UIColor systemRedColor];
    }
    return cell;
}

#pragma mark - Actions

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == DYYYDiagnosticsSectionCapture) {
        if (indexPath.row == DYYYDiagnosticsCaptureRowGeneralNow) {
            [self collectProfile:DYYYDiagnosticsProfileGeneral];
        } else if (indexPath.row == DYYYDiagnosticsCaptureRowCommentNow) {
            [self collectProfile:DYYYDiagnosticsProfileCommentPanel];
        }
        return;
    }
    if (indexPath.section != DYYYDiagnosticsSectionReports) {
        return;
    }
    if (indexPath.row == DYYYDiagnosticsReportsRowShareLatest) {
        [self shareLatestReport];
    } else if (indexPath.row == DYYYDiagnosticsReportsRowClear) {
        [self confirmClearReports];
    }
}

- (void)profileChanged:(UISegmentedControl *)control {
    DYYYDiagnosticsProfile profile = control.selectedSegmentIndex == 0 ? DYYYDiagnosticsProfileGeneral : DYYYDiagnosticsProfileCommentPanel;
    [DYYYDiagnosticsCollector setCaptureGestureProfile:profile];
}

- (void)optionSwitchChanged:(UISwitch *)toggle {
    NSString *key = toggle.accessibilityIdentifier;
    if ([key isEqualToString:DYYYDiagnosticsGestureEnabledKey]) {
        [DYYYDiagnosticsCollector setCaptureGestureEnabled:toggle.on];
        [DYYYUtils showToast:toggle.on ? @"四指长按诊断已启用" : @"四指长按诊断已关闭"];
        return;
    }
    if (([key isEqualToString:DYYYDiagnosticsIncludeTextKey] || [key isEqualToString:DYYYDiagnosticsIncludeScreenshotKey]) && toggle.on) {
        NSString *title = [key isEqualToString:DYYYDiagnosticsIncludeTextKey] ? @"包含界面文字" : @"附带页面截图";
        NSString *message = [key isEqualToString:DYYYDiagnosticsIncludeTextKey]
                                ? @"报告可能包含昵称、评论正文和输入内容。请仅在确认可以分享这些内容时开启。"
                                : @"截图可能包含头像、昵称、评论正文及当前页面的其他可见信息。";
        toggle.on = NO;
        [DYYYBottomAlertView showAlertWithTitle:title
                                        message:message
                                      avatarURL:nil
                               cancelButtonText:@"取消"
                              confirmButtonText:@"确认开启"
                                   cancelAction:nil
                                    closeAction:nil
                                  confirmAction:^{
                                    toggle.on = YES;
                                    [self applyPrivacyToggle:toggle key:key];
                                  }];
        return;
    }
    [self applyPrivacyToggle:toggle key:key];
}

- (void)applyPrivacyToggle:(UISwitch *)toggle key:(NSString *)key {
    if ([key isEqualToString:DYYYDiagnosticsIncludeTextKey]) {
        [DYYYDiagnosticsCollector setIncludeVisibleText:toggle.on];
    } else if ([key isEqualToString:DYYYDiagnosticsIncludeScreenshotKey]) {
        [DYYYDiagnosticsCollector setIncludeScreenshot:toggle.on];
    } else if ([key isEqualToString:DYYYDiagnosticsIncludeConstraintsKey]) {
        [DYYYDiagnosticsCollector setIncludeConstraints:toggle.on];
    } else if ([key isEqualToString:DYYYDiagnosticsIncludeRuntimeKey]) {
        [DYYYDiagnosticsCollector setIncludeRuntimeDetails:toggle.on];
    }
}

- (void)collectProfile:(DYYYDiagnosticsProfile)profile {
    if (self.collecting) {
        [DYYYUtils showToast:@"诊断任务正在运行"];
        return;
    }
    self.collecting = YES;
    [[DYYYDiagnosticsCollector sharedCollector]
        collectCurrentStateWithProfile:profile
                           completion:^(NSArray<NSURL *> *fileURLs, NSError *error) {
                             self.collecting = NO;
                             [self.tableView reloadData];
                             if (error) {
                                 [DYYYUtils showToast:[NSString stringWithFormat:@"采集失败：%@", error.localizedDescription]];
                             } else {
                                 [DYYYUtils showToast:[NSString stringWithFormat:@"已生成 %lu 个诊断文件", (unsigned long)fileURLs.count]];
                             }
                           }];
}

- (void)shareLatestReport {
    NSArray<NSURL *> *fileURLs = [DYYYDiagnosticsCollector latestReportFileURLs];
    if (fileURLs.count == 0) {
        [DYYYUtils showToast:@"还没有可分享的诊断报告"];
        return;
    }
    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:fileURLs applicationActivities:nil];
    UIPopoverPresentationController *popover = activityController.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        popover.permittedArrowDirections = 0;
    }
    [self presentViewController:activityController animated:YES completion:nil];
}

- (void)confirmClearReports {
    [DYYYBottomAlertView showAlertWithTitle:@"清除诊断报告"
                                    message:@"将删除全部 JSON、TXT 和截图文件，不影响 DYYY 设置。"
                                  avatarURL:nil
                           cancelButtonText:@"取消"
                          confirmButtonText:@"全部清除"
                               cancelAction:nil
                                closeAction:nil
                              confirmAction:^{
                                NSError *error = nil;
                                if ([DYYYDiagnosticsCollector clearReports:&error]) {
                                    [DYYYUtils showToast:@"诊断报告已清除"];
                                } else {
                                    [DYYYUtils showToast:[NSString stringWithFormat:@"清除失败：%@", error.localizedDescription]];
                                }
                                [self.tableView reloadData];
                              }];
}

@end
