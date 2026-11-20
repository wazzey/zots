#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Tweak.h"

// Every font Spotify builds comes from a UIFont factory, so wrapping the factories turns the whole UI monospaced.
static _Thread_local BOOL sInside;

static UIFont *monospaced(UIFont *font) {
    if (!font || sInside) return font;
    NSString *family = font.familyName.lowercaseString;
    if ([family containsString:@"icon"] || [family containsString:@"glyph"] || [family containsString:@"emoji"]) return font;

    UIFontDescriptor *descriptor = font.fontDescriptor;
    UIFontWeight weight = [[descriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait] doubleValue];
    if (weight == 0 && (descriptor.symbolicTraits & UIFontDescriptorTraitBold)) weight = UIFontWeightBold;

    sInside = YES;
    UIFont *mono = [UIFont monospacedSystemFontOfSize:font.pointSize weight:weight];
    sInside = NO;
    return mono ?: font;
}

// Lowercases each attribute run on its own so styling survives. Runs whose length would change are left alone.
static NSAttributedString *lowercased(NSAttributedString *text) {
    if (!text.length) return text;
    NSMutableAttributedString *result = [text mutableCopy];
    [text enumerateAttributesInRange:NSMakeRange(0, text.length) options:0 usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
        NSString *run = [text.string substringWithRange:range];
        NSString *lower = run.lowercaseString;
        if (lower.length == run.length) [result replaceCharactersInRange:range withString:lower];
    }];
    return result;
}

int EeveeInstallTextTheme(BOOL monospace, BOOL lowercase, BOOL square) {
    static dispatch_once_t once;
    __block int count = 0;
    dispatch_once(&once, ^{
        if (lowercase) {
            Method plain = class_getInstanceMethod(UILabel.class, @selector(setText:));
            if (plain) {
                void (*orig)(id, SEL, NSString *) = (void *)method_getImplementation(plain);
                method_setImplementation(plain, imp_implementationWithBlock(^(id self_, NSString *text) {
                    orig(self_, @selector(setText:), text.lowercaseString);
                }));
                count++;
            }
            Method attributed = class_getInstanceMethod(UILabel.class, @selector(setAttributedText:));
            if (attributed) {
                void (*orig)(id, SEL, NSAttributedString *) = (void *)method_getImplementation(attributed);
                method_setImplementation(attributed, imp_implementationWithBlock(^(id self_, NSAttributedString *text) {
                    orig(self_, @selector(setAttributedText:), lowercased(text));
                }));
                count++;
            }
        }

        if (square) {
            Method corners = class_getInstanceMethod(CALayer.class, @selector(setCornerRadius:));
            if (corners) {
                void (*orig)(id, SEL, CGFloat) = (void *)method_getImplementation(corners);
                method_setImplementation(corners, imp_implementationWithBlock(^(id self_, CGFloat radius) {
                    orig(self_, @selector(setCornerRadius:), 0);
                }));
                count++;
            }
        }

        if (!monospace) return;
        Method named = class_getClassMethod(UIFont.class, @selector(fontWithName:size:));
        if (named) {
            UIFont *(*orig)(id, SEL, NSString *, CGFloat) = (void *)method_getImplementation(named);
            method_setImplementation(named, imp_implementationWithBlock(^UIFont *(id self_, NSString *name, CGFloat size) {
                return monospaced(orig(self_, @selector(fontWithName:size:), name, size));
            }));
            count++;
        }

        Method described = class_getClassMethod(UIFont.class, @selector(fontWithDescriptor:size:));
        if (described) {
            UIFont *(*orig)(id, SEL, UIFontDescriptor *, CGFloat) = (void *)method_getImplementation(described);
            method_setImplementation(described, imp_implementationWithBlock(^UIFont *(id self_, UIFontDescriptor *descriptor, CGFloat size) {
                return monospaced(orig(self_, @selector(fontWithDescriptor:size:), descriptor, size));
            }));
            count++;
        }

        for (NSString *name in @[@"systemFontOfSize:", @"boldSystemFontOfSize:", @"italicSystemFontOfSize:"]) {
            SEL sel = NSSelectorFromString(name);
            Method m = class_getClassMethod(UIFont.class, sel);
            if (!m) continue;
            UIFont *(*orig)(id, SEL, CGFloat) = (void *)method_getImplementation(m);
            method_setImplementation(m, imp_implementationWithBlock(^UIFont *(id self_, CGFloat size) {
                return monospaced(orig(self_, sel, size));
            }));
            count++;
        }

        Method weighted = class_getClassMethod(UIFont.class, @selector(systemFontOfSize:weight:));
        if (weighted) {
            UIFont *(*orig)(id, SEL, CGFloat, UIFontWeight) = (void *)method_getImplementation(weighted);
            method_setImplementation(weighted, imp_implementationWithBlock(^UIFont *(id self_, CGFloat size, UIFontWeight weight) {
                return monospaced(orig(self_, @selector(systemFontOfSize:weight:), size, weight));
            }));
            count++;
        }

        Method styled = class_getClassMethod(UIFont.class, @selector(preferredFontForTextStyle:));
        if (styled) {
            UIFont *(*orig)(id, SEL, UIFontTextStyle) = (void *)method_getImplementation(styled);
            method_setImplementation(styled, imp_implementationWithBlock(^UIFont *(id self_, UIFontTextStyle style) {
                return monospaced(orig(self_, @selector(preferredFontForTextStyle:), style));
            }));
            count++;
        }

        Method traited = class_getClassMethod(UIFont.class, @selector(preferredFontForTextStyle:compatibleWithTraitCollection:));
        if (traited) {
            UIFont *(*orig)(id, SEL, UIFontTextStyle, UITraitCollection *) = (void *)method_getImplementation(traited);
            method_setImplementation(traited, imp_implementationWithBlock(^UIFont *(id self_, UIFontTextStyle style, UITraitCollection *traits) {
                return monospaced(orig(self_, @selector(preferredFontForTextStyle:compatibleWithTraitCollection:), style, traits));
            }));
            count++;
        }
    });
    return count;
}
