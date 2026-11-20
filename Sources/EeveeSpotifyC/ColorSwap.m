#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "Tweak.h"

// Spotify's base surface (#121212) and brand greens are each one token, so they're swapped where colors are born.
static BOOL sBaseOn;
static BOOL sTintElevated;
static CGFloat sBase[3];
static BOOL sAccentOn;
static CGFloat sAccent[3];
static const uint32_t kGreens[] = {0x1ED760, 0x1DB954};
static atomic_long sGreyHits, sGreenHits, sInitHits;

// Colour schemes also tint the lighter card greys, keeping how much lighter each one is than the base.
static BOOL isBaseGrey(const CGFloat *c, size_t n) {
    CGFloat ceiling = sTintElevated ? 0.30 : 0.10;
    if (n == 2) return c[0] > 0.01 && c[0] <= ceiling;
    if (n < 3) return NO;
    return c[0] > 0.01 && c[0] <= ceiling && fabs(c[0] - c[1]) < 0.02 && fabs(c[1] - c[2]) < 0.02;
}

static CGColorRef copyBaseShade(CGFloat grey, CGFloat alpha) {
    CGFloat lift = sTintElevated ? MAX(0, grey - 0.07) : 0;
    return CGColorCreateSRGB(MIN(1, sBase[0] + lift), MIN(1, sBase[1] + lift), MIN(1, sBase[2] + lift), alpha);
}

// The darker green variants keep their relation to the token as the same shade of the accent.
static BOOL swapGreen(CGFloat *r, CGFloat *g, CGFloat *b) {
    if (!sAccentOn) return NO;
    for (size_t i = 0; i < sizeof(kGreens) / sizeof(kGreens[0]); i++) {
        CGFloat gr = ((kGreens[i] >> 16) & 0xFF) / 255.0, gg = ((kGreens[i] >> 8) & 0xFF) / 255.0, gb = (kGreens[i] & 0xFF) / 255.0;
        if (fabs(*r - gr) > 0.01 || fabs(*g - gg) > 0.01 || fabs(*b - gb) > 0.01) continue;
        CGFloat factor = MAX(gr, MAX(gg, gb)) / (0xD7 / 255.0);
        *r = MIN(1, sAccent[0] * factor);
        *g = MIN(1, sAccent[1] * factor);
        *b = MIN(1, sAccent[2] * factor);
        return YES;
    }
    return NO;
}

// Layers get colors from background threads too, so only CoreGraphics here, no UIKit objects.
static CGColorRef copySwapped(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID()) return NULL;
    size_t n = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    if (sBaseOn && isBaseGrey(c, n)) {
        atomic_fetch_add_explicit(&sGreyHits, 1, memory_order_relaxed);
        return copyBaseShade(c[0], CGColorGetAlpha(color));
    }
    if (n != 4) return NULL;
    CGFloat r = c[0], g = c[1], b = c[2];
    if (!swapGreen(&r, &g, &b)) return NULL;
    atomic_fetch_add_explicit(&sGreenHits, 1, memory_order_relaxed);
    CGFloat out[] = {r, g, b, c[3]};
    return CGColorCreate(CGColorGetColorSpace(color), out);
}

static id swappedObject(id value) {
    if (!value || CFGetTypeID((__bridge CFTypeRef)value) != CGColorGetTypeID()) return value;
    CGColorRef swapped = copySwapped((__bridge CGColorRef)value);
    return swapped ? (__bridge_transfer id)swapped : value;
}

#define SWIZZLE_CGCOLOR_SETTER(cls, sel) do { \
    Method m = class_getInstanceMethod(cls, sel); \
    if (!m) break; \
    void (*orig)(id, SEL, CGColorRef) = (void (*)(id, SEL, CGColorRef))method_getImplementation(m); \
    method_setImplementation(m, imp_implementationWithBlock(^(id self_, CGColorRef color) { \
        CGColorRef swapped = copySwapped(color); \
        orig(self_, sel, swapped ?: color); \
        if (swapped) CGColorRelease(swapped); \
    })); \
    count++; \
} while (0)

int EeveeInstallColorSwaps(NSInteger baseRGB, BOOL tintElevated, NSInteger accentRGB) {
    static dispatch_once_t once;
    __block int count = 0;
    dispatch_once(&once, ^{
        sBaseOn = baseRGB >= 0 && baseRGB <= 0xFFFFFF;
        sTintElevated = tintElevated;
        sBase[0] = ((baseRGB >> 16) & 0xFF) / 255.0;
        sBase[1] = ((baseRGB >> 8) & 0xFF) / 255.0;
        sBase[2] = (baseRGB & 0xFF) / 255.0;
        sAccentOn = accentRGB >= 0 && accentRGB <= 0xFFFFFF;
        sAccent[0] = ((accentRGB >> 16) & 0xFF) / 255.0;
        sAccent[1] = ((accentRGB >> 8) & 0xFF) / 255.0;
        sAccent[2] = (accentRGB & 0xFF) / 255.0;
        if (!sBaseOn && !sAccentOn) return;

        SWIZZLE_CGCOLOR_SETTER(CALayer.class, @selector(setBackgroundColor:));

        Method colors = class_getInstanceMethod(CAGradientLayer.class, @selector(setColors:));
        if (colors) {
            void (*orig)(id, SEL, NSArray *) = (void (*)(id, SEL, NSArray *))method_getImplementation(colors);
            method_setImplementation(colors, imp_implementationWithBlock(^(id self_, NSArray *values) {
                NSMutableArray *mapped = nil;
                for (NSUInteger i = 0; i < values.count; i++) {
                    id swapped = swappedObject(values[i]);
                    if (swapped == values[i]) continue;
                    if (!mapped) mapped = [values mutableCopy];
                    mapped[i] = swapped;
                }
                orig(self_, @selector(setColors:), mapped ?: values);
            }));
            count++;
        }

        if (!sAccentOn) return;
        SWIZZLE_CGCOLOR_SETTER(CAShapeLayer.class, @selector(setFillColor:));
        SWIZZLE_CGCOLOR_SETTER(CAShapeLayer.class, @selector(setStrokeColor:));

        Method init = class_getInstanceMethod(UIColor.class, @selector(initWithRed:green:blue:alpha:));
        if (init) {
            UIColor *(*orig)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat) = (void *)method_getImplementation(init);
            method_setImplementation(init, imp_implementationWithBlock(^UIColor *(id self_, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
                if (swapGreen(&r, &g, &b)) atomic_fetch_add_explicit(&sInitHits, 1, memory_order_relaxed);
                return orig(self_, @selector(initWithRed:green:blue:alpha:), r, g, b, a);
            }));
            count++;
        }
        Method make = class_getClassMethod(UIColor.class, @selector(colorWithRed:green:blue:alpha:));
        if (make) {
            UIColor *(*orig)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat) = (void *)method_getImplementation(make);
            method_setImplementation(make, imp_implementationWithBlock(^UIColor *(id self_, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
                if (swapGreen(&r, &g, &b)) atomic_fetch_add_explicit(&sInitHits, 1, memory_order_relaxed);
                return orig(self_, @selector(colorWithRed:green:blue:alpha:), r, g, b, a);
            }));
            count++;
        }
        Method values = class_getInstanceMethod(CAKeyframeAnimation.class, @selector(setValues:));
        if (values) {
            void (*orig)(id, SEL, NSArray *) = (void (*)(id, SEL, NSArray *))method_getImplementation(values);
            method_setImplementation(values, imp_implementationWithBlock(^(id self_, NSArray *list) {
                NSMutableArray *mapped = nil;
                for (NSUInteger i = 0; i < list.count; i++) {
                    id swapped = swappedObject(list[i]);
                    if (swapped == list[i]) continue;
                    if (!mapped) mapped = [list mutableCopy];
                    mapped[i] = swapped;
                }
                orig(self_, @selector(setValues:), mapped ?: list);
            }));
            count++;
        }
        for (NSString *name in @[@"setFromValue:", @"setToValue:"]) {
            SEL sel = NSSelectorFromString(name);
            Method m = class_getInstanceMethod(CABasicAnimation.class, sel);
            if (!m) continue;
            void (*orig)(id, SEL, id) = (void (*)(id, SEL, id))method_getImplementation(m);
            method_setImplementation(m, imp_implementationWithBlock(^(id self_, id value) {
                orig(self_, sel, swappedObject(value));
            }));
            count++;
        }
    });
    return count;
}

void EeveeColorSwapStats(long *grey, long *green, long *uiColor) {
    *grey = atomic_load_explicit(&sGreyHits, memory_order_relaxed);
    *green = atomic_load_explicit(&sGreenHits, memory_order_relaxed);
    *uiColor = atomic_load_explicit(&sInitHits, memory_order_relaxed);
}
