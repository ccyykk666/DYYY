#import "DYYYInstagramTabBarView.h"

#import <objc/message.h>

static const CGFloat kDYYYInstagramBarHorizontalInset = 22.0;
static const CGFloat kDYYYInstagramBarHeight = 60.0;
static const CGFloat kDYYYInstagramButtonHorizontalInset = 10.0;
static const CGFloat kDYYYInstagramIndicatorInset = 5.0;

static UIVisualEffect *DYYYInstagramGlassEffect(void) {
    Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
    SEL effectSelector = NSSelectorFromString(@"effectWithStyle:");
    if (glassEffectClass && [glassEffectClass respondsToSelector:effectSelector]) {
        // Instagram 435.1.0 uses UIGlassEffectStyleRegular (raw value 1),
        // enables interaction, then applies its IGDS tab-bar tint.
        id effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassEffectClass, effectSelector, 1);
        SEL interactiveSelector = NSSelectorFromString(@"setInteractive:");
        if ([effect respondsToSelector:interactiveSelector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, interactiveSelector, YES);
        }
        return effect;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
}

@interface DYYYInstagramTabBarView () <UIGestureRecognizerDelegate>

@property(nonatomic, strong) UIView *shadowView;
@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, strong) UIVisualEffectView *indicatorView;
@property(nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property(nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;
@property(nonatomic, strong) UISelectionFeedbackGenerator *feedbackGenerator;
@property(nonatomic, assign, readwrite) NSUInteger selectedIndex;
@property(nonatomic, assign) CGPoint dragStartIndicatorCenter;

@end

@implementation DYYYInstagramTabBarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }

    self.backgroundColor = UIColor.clearColor;
    self.isAccessibilityElement = NO;

    _shadowView = [[UIView alloc] initWithFrame:CGRectZero];
    _shadowView.backgroundColor = UIColor.clearColor;
    _shadowView.userInteractionEnabled = NO;
    _shadowView.layer.shadowColor = UIColor.blackColor.CGColor;
    _shadowView.layer.shadowOpacity = 0.08f;
    _shadowView.layer.shadowOffset = CGSizeMake(0.0, 2.0);
    _shadowView.layer.shadowRadius = 24.0;
    [self addSubview:_shadowView];

    _glassView = [[UIVisualEffectView alloc] initWithEffect:nil];
    _glassView.clipsToBounds = YES;
    _glassView.layer.cornerCurve = kCACornerCurveContinuous;
    _glassView.isAccessibilityElement = NO;
    [self addSubview:_glassView];

    _indicatorView = [[UIVisualEffectView alloc] initWithEffect:nil];
    _indicatorView.userInteractionEnabled = NO;
    _indicatorView.clipsToBounds = YES;
    _indicatorView.layer.cornerCurve = kCACornerCurveContinuous;
    [_glassView.contentView addSubview:_indicatorView];

    _buttons = [NSMutableArray arrayWithCapacity:5];
    _selectedIndex = NSNotFound;

    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    _panGestureRecognizer.delegate = self;
    _panGestureRecognizer.maximumNumberOfTouches = 1;
    [_glassView.contentView addGestureRecognizer:_panGestureRecognizer];

    [self refreshAppearance];
    return self;
}

- (void)refreshAppearance {
    self.glassView.effect = DYYYInstagramGlassEffect();

    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    UIBlurEffectStyle indicatorStyle = dark ? UIBlurEffectStyleSystemUltraThinMaterialLight : UIBlurEffectStyleSystemUltraThinMaterialDark;
    self.indicatorView.effect = [UIBlurEffect effectWithStyle:indicatorStyle];
    self.indicatorView.alpha = dark ? 0.60 : 0.38;

    UIColor *tintColor = UIColor.labelColor;
    for (UIButton *button in self.buttons) {
        button.tintColor = tintColor;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
        [self refreshAppearance];
    }
}

- (void)configureWithNormalImages:(NSArray<UIImage *> *)normalImages
                   selectedImages:(NSArray<UIImage *> *)selectedImages
              accessibilityLabels:(NSArray<NSString *> *)accessibilityLabels
                    selectedIndex:(NSUInteger)selectedIndex {
    if (normalImages.count != selectedImages.count || normalImages.count != accessibilityLabels.count) {
        return;
    }

    while (self.buttons.count > normalImages.count) {
        [self.buttons.lastObject removeFromSuperview];
        [self.buttons removeLastObject];
    }

    while (self.buttons.count < normalImages.count) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.backgroundColor = UIColor.clearColor;
        button.adjustsImageWhenHighlighted = NO;
        button.imageView.contentMode = UIViewContentModeCenter;
        [button addTarget:self action:@selector(tabButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.glassView.contentView addSubview:button];
        [self.buttons addObject:button];
    }

    [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
      [button setImage:normalImages[index] forState:UIControlStateNormal];
      [button setImage:selectedImages[index] forState:UIControlStateSelected];
      button.accessibilityLabel = accessibilityLabels[index];
      button.accessibilityTraits = UIAccessibilityTraitButton;
      button.tag = index;
    }];

    self.selectedIndex = selectedIndex < self.buttons.count ? selectedIndex : 0;
    [self updateButtonSelection];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat availableWidth = MAX(0.0, CGRectGetWidth(self.bounds) - 2.0 * kDYYYInstagramBarHorizontalInset);
    CGFloat y = CGRectGetHeight(self.bounds) >= kDYYYInstagramBarHeight ? 1.0 : 0.0;
    CGRect glassFrame = CGRectMake(kDYYYInstagramBarHorizontalInset, y, availableWidth, MIN(kDYYYInstagramBarHeight, CGRectGetHeight(self.bounds)));
    self.shadowView.frame = glassFrame;
    self.glassView.frame = glassFrame;

    CGFloat cornerRadius = CGRectGetHeight(glassFrame) * 0.5;
    self.shadowView.layer.cornerRadius = cornerRadius;
    self.glassView.layer.cornerRadius = cornerRadius;
    self.shadowView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.shadowView.bounds cornerRadius:cornerRadius].CGPath;

    NSUInteger count = self.buttons.count;
    if (count == 0 || availableWidth <= 2.0 * kDYYYInstagramButtonHorizontalInset) {
        self.indicatorView.hidden = YES;
        return;
    }

    self.indicatorView.hidden = NO;
    CGFloat buttonWidth = (availableWidth - 2.0 * kDYYYInstagramButtonHorizontalInset) / count;
    CGFloat buttonHeight = CGRectGetHeight(self.glassView.bounds);
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
      button.frame = CGRectMake(kDYYYInstagramButtonHorizontalInset + buttonWidth * index, 0.0, buttonWidth, buttonHeight);
    }];

    CGFloat indicatorWidth = buttonWidth + 20.0;
    self.indicatorView.bounds = CGRectMake(0.0, 0.0, indicatorWidth - 2.0 * kDYYYInstagramIndicatorInset, buttonHeight - 2.0 * kDYYYInstagramIndicatorInset);
    self.indicatorView.layer.cornerRadius = CGRectGetHeight(self.indicatorView.bounds) * 0.5;
    if (self.panGestureRecognizer.state == UIGestureRecognizerStatePossible) {
        self.indicatorView.center = [self centerForButtonAtIndex:self.selectedIndex];
    }
    [self.glassView.contentView bringSubviewToFront:self.indicatorView];
    for (UIButton *button in self.buttons) {
        [self.glassView.contentView bringSubviewToFront:button];
    }
}

- (CGPoint)centerForButtonAtIndex:(NSUInteger)index {
    if (index >= self.buttons.count) {
        return CGPointMake(CGRectGetMidX(self.glassView.bounds), CGRectGetMidY(self.glassView.bounds));
    }
    return self.buttons[index].center;
}

- (void)updateButtonSelection {
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
      BOOL selected = index == self.selectedIndex;
      button.selected = selected;
      button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex animated:(BOOL)animated {
    if (selectedIndex >= self.buttons.count) {
        return;
    }

    _selectedIndex = selectedIndex;
    [self updateButtonSelection];
    UIGestureRecognizerState panState = self.panGestureRecognizer.state;
    if (panState == UIGestureRecognizerStateBegan || panState == UIGestureRecognizerStateChanged) {
        return;
    }
    CGPoint targetCenter = [self centerForButtonAtIndex:selectedIndex];
    void (^animations)(void) = ^{
      self.indicatorView.center = targetCenter;
      [self applyIndicatorSqueeze:0.0];
    };
    if (animated && self.window) {
        [UIView animateWithDuration:0.35 delay:0.0 usingSpringWithDamping:0.78 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:animations completion:nil];
    } else {
        animations();
    }
}

- (void)tabButtonTapped:(UIButton *)button {
    NSUInteger index = (NSUInteger)button.tag;
    if (index >= self.buttons.count) {
        return;
    }
    [self setSelectedIndex:index animated:YES];
    if (self.selectionHandler) {
        self.selectionHandler(index);
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.panGestureRecognizer || self.buttons.count < 2) {
        return NO;
    }
    CGPoint velocity = [gestureRecognizer velocityInView:self.glassView.contentView];
    return fabs(velocity.x) > fabs(velocity.y);
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)gestureRecognizer {
    if (self.buttons.count == 0) {
        return;
    }

    switch (gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan: {
            self.dragStartIndicatorCenter = [self centerForButtonAtIndex:self.selectedIndex];
            self.feedbackGenerator = [[UISelectionFeedbackGenerator alloc] init];
            [self.feedbackGenerator prepare];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGPoint location = [gestureRecognizer locationInView:self.glassView.contentView];
            CGPoint firstCenter = [self centerForButtonAtIndex:0];
            CGPoint lastCenter = [self centerForButtonAtIndex:self.buttons.count - 1];
            CGFloat x = location.x;
            if (x < firstCenter.x) {
                x = firstCenter.x + (x - firstCenter.x) * 0.20;
            } else if (x > lastCenter.x) {
                x = lastCenter.x + (x - lastCenter.x) * 0.20;
            }

            CGFloat buttonWidth = self.buttons.firstObject.bounds.size.width;
            CGFloat squeeze = buttonWidth > 0.0 ? MIN(1.0, fabs(x - [self centerForButtonAtIndex:self.selectedIndex].x) / buttonWidth) : 0.0;
            self.indicatorView.center = CGPointMake(x, self.dragStartIndicatorCenter.y);
            [self applyIndicatorSqueeze:squeeze];

            CGFloat clampedX = MIN(MAX(location.x, firstCenter.x), lastCenter.x);
            NSUInteger nearestIndex = (NSUInteger)llround((clampedX - firstCenter.x) / MAX(buttonWidth, 1.0));
            nearestIndex = MIN(nearestIndex, self.buttons.count - 1);
            if (nearestIndex != self.selectedIndex) {
                _selectedIndex = nearestIndex;
                [self updateButtonSelection];
                [self.feedbackGenerator selectionChanged];
                [self.feedbackGenerator prepare];
                if (self.selectionHandler) {
                    self.selectionHandler(nearestIndex);
                }
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            self.feedbackGenerator = nil;
            [self setSelectedIndex:self.selectedIndex animated:YES];
            break;
        default:
            break;
    }
}

- (void)applyIndicatorSqueeze:(CGFloat)magnitude {
    CGFloat clampedMagnitude = MIN(MAX(magnitude, 0.0), 1.0);
    CGFloat buttonWidth = self.buttons.firstObject.bounds.size.width;
    CGFloat normalWidth = buttonWidth + 10.0;
    CGFloat normalHeight = MAX(0.0, CGRectGetHeight(self.glassView.bounds) - 2.0 * kDYYYInstagramIndicatorInset);
    CGFloat width = normalWidth + 3.0 * clampedMagnitude;
    CGFloat height = normalHeight - 10.0 * clampedMagnitude;
    self.indicatorView.bounds = CGRectMake(0.0, 0.0, width, height);
    self.indicatorView.layer.cornerRadius = height * 0.5;
}

@end
