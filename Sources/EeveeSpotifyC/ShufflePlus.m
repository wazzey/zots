#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Tweak.h"

@protocol EeveeShufflePlayer
- (id)getQueueWithCallback:(void (^)(id queue))callback;
- (void)fetchState:(void (^)(id state))callback reverseCap:(unsigned long long)reverseCap futureCap:(unsigned long long)futureCap on:(id)queue;
- (id)setQueue:(id)queue;
@end

@protocol EeveeShuffleState
- (id)options;
- (id)contextURI;
- (id)sessionID;
- (NSArray *)future;
- (BOOL)shufflingContext;
- (NSArray *)nextTracks;
- (void)setNextTracks:(NSArray *)tracks;
- (BOOL)spt_isQueued;
- (BOOL)spt_trackIsDelimiter;
@end

// Spotify's shuffle replays orders it has used before, so each new shuffled play is dealt again with Fisher-Yates.
static NSString *sLastPlay;
static NSObject *sLock;

static BOOL answers(id object, SEL selector) {
    return object && [object respondsToSelector:selector];
}

static NSArray *dealt(NSArray *tracks) {
    NSMutableArray *queued = [NSMutableArray array];
    NSMutableArray *context = [NSMutableArray array];
    NSMutableArray *tail = [NSMutableArray array];
    for (id<EeveeShuffleState> track in tracks) {
        if (answers(track, @selector(spt_trackIsDelimiter)) && track.spt_trackIsDelimiter) {
            [tail addObject:track];
        } else if (tail.count == 0 && answers(track, @selector(spt_isQueued)) && track.spt_isQueued) {
            [queued addObject:track];
        } else if (tail.count == 0) {
            [context addObject:track];
        } else {
            [tail addObject:track];
        }
    }
    for (NSUInteger i = context.count; i > 1; i--) {
        [context exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
    }
    [queued addObjectsFromArray:context];
    [queued addObjectsFromArray:tail];
    return queued;
}

static void reshuffle(id<EeveeShufflePlayer> player) {
    [player fetchState:^(id<EeveeShuffleState> state) {
        NSArray *future = answers(state, @selector(future)) ? state.future : nil;
        if (future.count < 2) return;
        [player getQueueWithCallback:^(id<EeveeShuffleState> queue) {
            if (!answers(queue, @selector(setNextTracks:))) return;
            [queue setNextTracks:dealt(future)];
            [player setQueue:queue];
            NSLog(@"[EeveeSpotify][ShufflePlus] dealt %lu tracks", (unsigned long)future.count);
        }];
    } reverseCap:0 futureCap:5000 on:dispatch_get_main_queue()];
}

int EeveeInstallShufflePlus(void) {
    static dispatch_once_t once;
    __block int count = 0;
    dispatch_once(&once, ^{
        sLock = [NSObject new];
        Class player = NSClassFromString(@"SPTEsperantoPlayer");
        SEL update = NSSelectorFromString(@"globalPlayerSubscription:gotStateUpdate:");
        Method method = player ? class_getInstanceMethod(player, update) : NULL;
        if (!method || !class_getInstanceMethod(player, @selector(setQueue:))
            || !class_getInstanceMethod(player, @selector(getQueueWithCallback:))
            || !class_getInstanceMethod(player, @selector(fetchState:reverseCap:futureCap:on:))) return;

        void (*orig)(id, SEL, id, id) = (void *)method_getImplementation(method);
        method_setImplementation(method, imp_implementationWithBlock(^(id self_, id subscription, id<EeveeShuffleState> state) {
            orig(self_, update, subscription, state);
            id<EeveeShuffleState> options = answers(state, @selector(options)) ? state.options : nil;
            BOOL shuffling = answers(options, @selector(shufflingContext)) && options.shufflingContext;
            NSString *play = nil;
            if (shuffling && answers(state, @selector(contextURI)) && answers(state, @selector(sessionID))) {
                play = [NSString stringWithFormat:@"%@|%@", state.contextURI, state.sessionID];
            }
            @synchronized (sLock) {
                if (!play) {
                    sLastPlay = nil;
                    return;
                }
                if ([play isEqualToString:sLastPlay]) return;
                sLastPlay = play;
            }
            reshuffle(self_);
        }));
        count++;

        // The Shuffle row of the listening modes sheet reads Shuffle+ so it's clear which shuffle plays.
        Method plain = class_getInstanceMethod(UILabel.class, @selector(setText:));
        if (plain) {
            void (*orig)(id, SEL, NSString *) = (void *)method_getImplementation(plain);
            method_setImplementation(plain, imp_implementationWithBlock(^(id self_, NSString *text) {
                orig(self_, @selector(setText:), [text isEqualToString:@"Shuffle"] ? @"Shuffle+" : text);
            }));
            count++;
        }
        Method attributed = class_getInstanceMethod(UILabel.class, @selector(setAttributedText:));
        if (attributed) {
            void (*orig)(id, SEL, NSAttributedString *) = (void *)method_getImplementation(attributed);
            method_setImplementation(attributed, imp_implementationWithBlock(^(id self_, NSAttributedString *text) {
                if (![text.string isEqualToString:@"Shuffle"]) {
                    orig(self_, @selector(setAttributedText:), text);
                    return;
                }
                NSMutableAttributedString *renamed = [text mutableCopy];
                [renamed replaceCharactersInRange:NSMakeRange(0, renamed.length) withString:@"Shuffle+"];
                orig(self_, @selector(setAttributedText:), renamed);
            }));
            count++;
        }
    });
    return count;
}
