#import "DYYYInstagramTabBarView.h"

#import <math.h>
#import <objc/message.h>

static const CGFloat kDYYYInstagramBarHorizontalInset = 22.0;
static const CGFloat kDYYYInstagramBarHeight = 60.0;
static const CGFloat kDYYYInstagramButtonHorizontalInset = 10.0;
static const CGFloat kDYYYInstagramIndicatorInset = 5.0;
static const CGFloat kDYYYInstagramRubberBandLimit = 20.0;
static const CGFloat kDYYYInstagramRubberBandCoefficient = 0.55;
static const NSTimeInterval kDYYYInstagramIndicatorAnimationDuration = 0.35;
static const CGFloat kDYYYInstagramIndicatorSpringDamping = 0.78;

static UIColor *DYYYInstagramGlassTintColor(BOOL darkAppearance) {
    return darkAppearance ? [UIColor.blackColor colorWithAlphaComponent:0.65] : [UIColor.whiteColor colorWithAlphaComponent:0.80];
}

static UIVisualEffect *DYYYInstagramGlassEffect(UIColor *tintColor) {
    Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
    SEL effectSelector = NSSelectorFromString(@"effectWithStyle:");
    if (glassEffectClass && [glassEffectClass respondsToSelector:effectSelector]) {
        // Instagram 435.1.0: UIGlassEffectStyleRegular (1), interactive=YES,
        // followed by its dynamic IGDS Liquid Glass tab-bar tint.
        id effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassEffectClass, effectSelector, 1);
        SEL interactiveSelector = NSSelectorFromString(@"setInteractive:");
        if ([effect respondsToSelector:interactiveSelector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, interactiveSelector, YES);
        }
        SEL tintSelector = NSSelectorFromString(@"setTintColor:");
        if ([effect respondsToSelector:tintSelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(effect, tintSelector, tintColor);
        }
        return effect;
    }

    // Instagram uses UIBlurEffectStyleSystemMaterial before the Liquid Glass
    // path is available.
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
}

static CGFloat DYYYInstagramRubberBandedOffset(CGFloat offset) {
    if (offset == 0.0) {
        return 0.0;
    }
    CGFloat normalized = fabs(offset) * kDYYYInstagramRubberBandCoefficient / kDYYYInstagramRubberBandLimit;
    CGFloat magnitude = kDYYYInstagramRubberBandLimit * (1.0 - 1.0 / (normalized + 1.0));
    return copysign(magnitude, offset);
}

@interface DYYYInstagramTabBarView () <UIGestureRecognizerDelegate>

@property(nonatomic, strong) UIView *shadowView;
@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, strong) UIVisualEffectView *indicatorView;
@property(nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property(nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;
@property(nonatomic, strong) UISelectionFeedbackGenerator *feedbackGenerator;
@property(nonatomic, assign, readwrite) NSUInteger selectedIndex;
@property(nonatomic, assign) CGFloat lastPanVelocityX;
@property(nonatomic, assign) NSUInteger panStartIndex;

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

    _glassView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
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
    _panStartIndex = NSNotFound;
    _darkAppearance = UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;

    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    _panGestureRecognizer.delegate = self;
    _panGestureRecognizer.maximumNumberOfTouches = 1;
    _panGestureRecognizer.cancelsTouchesInView = YES;
    [_glassView.contentView addGestureRecognizer:_panGestureRecognizer];

    [self refreshAppearance];
    return self;
}

- (void)refreshAppearance {
    UIColor *glassTintColor = DYYYInstagramGlassTintColor(self.isDarkAppearance);
    // Replacing the effect is intentional: UIVisualEffectView does not always
    // redraw when a UIGlassEffect instance is mutated in place during a theme switch.
    self.glassView.effect = DYYYInstagramGlassEffect(glassTintColor);

    UIBlurEffectStyle indicatorStyle = self.isDarkAppearance ? UIBlurEffectStyleSystemUltraThinMaterialLight : UIBlurEffectStyleSystemUltraThinMaterialDark;
    self.indicatorView.effect = [UIBlurEffect effectWithStyle:indicatorStyle];
    self.indicatorView.alpha = self.isDarkAppearance ? 0.60 : 0.38;

    UIColor *tintColor = self.isDarkAppearance ? UIColor.whiteColor : UIColor.blackColor;
    for (UIButton *button in self.buttons) {
        button.tintColor = tintColor;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self refreshAppearance];
    }
}

- (void)setDarkAppearance:(BOOL)darkAppearance {
    if (_darkAppearance == darkAppearance) {
        return;
    }
    _darkAppearance = darkAppearance;
    [self refreshAppearance];
}

- (void)configureWithNormalImages:(NSArray<UIImage *> *)normalImages
                   selectedImages:(NSArray<UIImage *> *)selectedImages
              accessibilityLabels:(NSArray<NSString *> *)accessibilityLabels
                    selectedIndex:(NSUInteger)selectedIndex {
    if (normalImages.count == 0 || normalImages.count != selectedImages.count || normalImages.count != accessibilityLabels.count) {
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
      button.tag = (NSInteger)index;
    }];

    _selectedIndex = selectedIndex < self.buttons.count ? selectedIndex : 0;
    [self updateButtonSelection];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat availableWidth = MAX(0.0, CGRectGetWidth(self.bounds) - 2.0 * kDYYYInstagramBarHorizontalInset);
    CGFloat barHeight = MIN(kDYYYInstagramBarHeight, CGRectGetHeight(self.bounds));
    CGFloat y = CGRectGetHeight(self.bounds) >= kDYYYInstagramBarHeight ? 1.0 : 0.0;
    CGRect glassFrame = CGRectMake(kDYYYInstagramBarHorizontalInset, y, availableWidth, barHeight);
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

    CGSize normalIndicatorSize = CGSizeMake(buttonWidth + 2.0 * kDYYYInstagramIndicatorInset, buttonHeight - 2.0 * kDYYYInstagramIndicatorInset);
    self.indicatorView.bounds = (CGRect){CGPointZero, normalIndicatorSize};
    self.indicatorView.layer.cornerRadius = normalIndicatorSize.height * 0.5;

    UIGestureRecognizerState panState = self.panGestureRecognizer.state;
    if (panState != UIGestureRecognizerStateBegan && panState != UIGestureRecognizerStateChanged) {
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
    CGFloat distance = targetCenter.x - self.indicatorView.center.x;
    CGFloat initialVelocity = fabs(distance) > 0.5 ? self.lastPanVelocityX / distance : 0.0;
    void (^animations)(void) = ^{
      self.indicatorView.center = targetCenter;
      [self applyIndicatorSqueeze:0.0];
    };
    if (animated && self.window) {
        [UIView animateWithDuration:kDYYYInstagramIndicatorAnimationDuration
                              delay:0.0
             usingSpringWithDamping:kDYYYInstagramIndicatorSpringDamping
              initialSpringVelocity:initialVelocity
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:animations
                         completion:nil];
    } else {
        animations();
    }
}

- (void)tabButtonTapped:(UIButton *)button {
    NSUInteger index = (NSUInteger)button.tag;
    if (index >= self.buttons.count) {
        return;
    }
    self.lastPanVelocityX = 0.0;
    [self setSelectedIndex:index animated:YES];
    if (self.selectionHandler) {
        self.selectionHandler(index);
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.panGestureRecognizer || self.buttons.count < 2) {
        return NO;
    }
    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.glassView.contentView];
    return fabs(velocity.x) > fabs(velocity.y);
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)gestureRecognizer {
    if (self.buttons.count < 2) {
        return;
    }

    switch (gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan:
            [self.indicatorView.layer removeAllAnimations];
            self.panStartIndex = self.selectedIndex;
            self.feedbackGenerator = [[UISelectionFeedbackGenerator alloc] init];
            [self.feedbackGenerator prepare];
            break;

        case UIGestureRecognizerStateChanged: {
            CGPoint location = [gestureRecognizer locationInView:self.glassView.contentView];
            CGPoint velocity = [gestureRecognizer velocityInView:self.glassView.contentView];
            self.lastPanVelocityX = velocity.x;

            CGPoint firstCenter = [self centerForButtonAtIndex:0];
            CGPoint lastCenter = [self centerForButtonAtIndex:self.buttons.count - 1];
            CGFloat displayedX = location.x;
            if (location.x < firstCenter.x) {
                displayedX = firstCenter.x + DYYYInstagramRubberBandedOffset(location.x - firstCenter.x);
            } else if (location.x > lastCenter.x) {
                displayedX = lastCenter.x + DYYYInstagramRubberBandedOffset(location.x - lastCenter.x);
            }

            CGFloat clampedX = MIN(MAX(location.x, firstCenter.x), lastCenter.x);
            CGFloat buttonWidth = MAX(self.buttons.firstObject.bounds.size.width, 1.0);
            NSUInteger nearestIndex = (NSUInteger)llround((clampedX - firstCenter.x) / buttonWidth);
            nearestIndex = MIN(nearestIndex, self.buttons.count - 1);

            CGPoint selectedCenter = [self centerForButtonAtIndex:nearestIndex];
            CGFloat squeeze = MIN(1.0, fabs(displayedX - selectedCenter.x) / buttonWidth);
            self.indicatorView.center = CGPointMake(displayedX, selectedCenter.y);
            [self applyIndicatorSqueeze:squeeze];

            if (nearestIndex != self.selectedIndex) {
                _selectedIndex = nearestIndex;
                [self updateButtonSelection];
                [self.feedbackGenerator selectionChanged];
                [self.feedbackGenerator prepare];
            }
            break;
        }

        case UIGestureRecognizerStateEnded: {
            NSUInteger selectedIndex = self.selectedIndex;
            NSUInteger startIndex = self.panStartIndex;
            self.feedbackGenerator = nil;
            self.panStartIndex = NSNotFound;
            [self setSelectedIndex:selectedIndex animated:YES];
            if (selectedIndex != startIndex && self.selectionHandler) {
                self.selectionHandler(selectedIndex);
            }
            break;
        }

        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            NSUInteger startIndex = self.panStartIndex;
            self.feedbackGenerator = nil;
            self.panStartIndex = NSNotFound;
            if (startIndex < self.buttons.count) {
                _selectedIndex = startIndex;
                [self updateButtonSelection];
            }
            [self setSelectedIndex:self.selectedIndex animated:YES];
            break;
        }

        default:
            break;
    }
}

- (void)applyIndicatorSqueeze:(CGFloat)magnitude {
    CGFloat clampedMagnitude = MIN(MAX(magnitude, 0.0), 1.0);
    CGFloat buttonWidth = self.buttons.firstObject.bounds.size.width;
    CGFloat normalWidth = buttonWidth + 2.0 * kDYYYInstagramIndicatorInset;
    CGFloat normalHeight = MAX(0.0, CGRectGetHeight(self.glassView.bounds) - 2.0 * kDYYYInstagramIndicatorInset);
    CGFloat width = normalWidth + 3.0 * clampedMagnitude;
    CGFloat height = normalHeight - 10.0 * clampedMagnitude;
    self.indicatorView.bounds = CGRectMake(0.0, 0.0, width, height);
    self.indicatorView.layer.cornerRadius = height * 0.5;
}

@end
