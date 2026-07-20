#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, DYYYNativeTabIconKind) {
    DYYYNativeTabIconKindHome,
    DYYYNativeTabIconKindReels,
    DYYYNativeTabIconKindDirect,
    DYYYNativeTabIconKindProfile,
    DYYYNativeTabIconKindUnknown = NSNotFound,
};

#ifdef __cplusplus
extern "C" {
#endif

UIImage *DYYYNativeTabIcon(DYYYNativeTabIconKind kind, BOOL selected);

#ifdef __cplusplus
}
#endif
