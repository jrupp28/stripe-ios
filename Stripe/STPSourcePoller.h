//
//  STPSourcePoller.h
//  Stripe
//
//  Created by Ben Guo on 1/26/17.
//  Copyright © 2017 Stripe, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "STPBlocks.h"

@class STPAPIClient;

NS_ASSUME_NONNULL_BEGIN

@interface STPSourcePoller : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithAPIClient:(STPAPIClient *)apiClient
                     clientSecret:(NSString *)clientSecret
                         sourceID:(NSString *)sourceID
                       completion:(STPSourceCompletionBlock)completion;

- (void)stopPolling;

@end

NS_ASSUME_NONNULL_END
