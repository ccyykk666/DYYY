#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, DYYYNativeTabIconKind) {
    DYYYNativeTabIconKindHome,
    DYYYNativeTabIconKindReels,
    DYYYNativeTabIconKindDirect,
    DYYYNativeTabIconKindProfile,
    DYYYNativeTabIconKindUnknown = NSNotFound,
};

UIImage *DYYYNativeTabIcon(DYYYNativeTabIconKind kind, BOOL selected);
