//
//  STPSourcePoller.m
//  Stripe
//
//  Created by Ben Guo on 1/26/17.
//  Copyright © 2017 Stripe, Inc. All rights reserved.
//

#import "STPAPIClient+Private.h"
#import "STPAPIRequest.h"
#import "STPSource.h"
#import "STPSourcePoller.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const DefaultPollInterval = 1.5;
static NSTimeInterval const MaxPollInterval = 24;
// Stop polling after 5 minutes
static NSTimeInterval const Timeout = 60*5;
// Stop polling after 5 consecutive non-200 responses
static NSTimeInterval const MaxRetries = 5;

@interface STPSourcePoller ()

@property (nonatomic, weak) STPAPIClient *apiClient;
@property (nonatomic) NSString *sourceID;
@property (nonatomic) NSString *clientSecret;
@property (nonatomic, copy) STPSourceCompletionBlock completion;
@property (nonatomic, nullable) STPSource *latestSource;
@property (nonatomic) NSTimeInterval pollInterval;
@property (nonatomic, nullable) NSURLSessionDataTask *dataTask;
@property (nonatomic, nullable) NSTimer *timer;
@property (nonatomic) NSDate *startTime;
@property (nonatomic) NSInteger retryCount;

@end

@implementation STPSourcePoller

- (instancetype)initWithAPIClient:(STPAPIClient *)apiClient
                     clientSecret:(NSString *)clientSecret
                         sourceID:(NSString *)sourceID
                       completion:(STPSourceCompletionBlock)completion {
    self = [super init];
    if (self) {
        _apiClient = apiClient;
        _sourceID = sourceID;
        _clientSecret = clientSecret;
        _completion = completion;
        _pollInterval = DefaultPollInterval;
        _startTime = [NSDate date];
        _retryCount = 0;
        [self pollAfter:0];
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(restartPolling)
                                   name:UIApplicationDidBecomeActiveNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(restartPolling)
                                   name:UIApplicationWillEnterForegroundNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(stopPolling)
                                   name:UIApplicationWillResignActiveNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(stopPolling)
                                   name:UIApplicationDidEnterBackgroundNotification
                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)pollAfter:(NSTimeInterval)interval {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                  target:self
                                                selector:@selector(poll)
                                                userInfo:nil
                                                 repeats:NO];
}

- (void)poll {
    NSTimeInterval totalTime = [[NSDate date] timeIntervalSinceDate:self.startTime];
    if (!self.apiClient || totalTime >= Timeout || self.retryCount >= MaxRetries) {
        [self stopPolling];
        return;
    }
    self.dataTask = [self.apiClient retrieveSourceWithId:self.sourceID
                                            clientSecret:self.clientSecret
                                      responseCompletion:^(STPSource *source, NSHTTPURLResponse *response, NSError *error) {
                                          [self continueWithSource:source response:response error:error];
                                      }];
}

- (void)restartPolling {
    if (!self.timer && !self.dataTask) {
        [self pollAfter:0];
    }
}

- (void)continueWithSource:(STPSource *)source
                  response:(NSHTTPURLResponse *)response
                     error:(NSError *)error {
    if (response) {
        NSUInteger status = response.statusCode;
        if (status >= 400 && status < 500) {
            // Don't retry requests that 4xx
            self.completion(self.latestSource, error);
            [self stopPolling];
        } else if (status == 200) {
            self.pollInterval = DefaultPollInterval;
            // Only call completion if source.status has changed
            if (!self.latestSource || source.status != self.latestSource.status) {
                self.completion(source, nil);
            }
            self.latestSource = source;
            if ([self shouldContinuePollingSource:source]) {
                [self pollAfter:self.pollInterval];
            } else {
                [self stopPolling];
            }
            self.retryCount = 0;
        } else {
            // Backoff on 500, otherwise reset poll interval
            if (status == 500) {
                self.pollInterval = MIN(self.pollInterval*2, MaxPollInterval);
            } else {
                self.pollInterval = DefaultPollInterval;
            }
            [self pollAfter:self.pollInterval];
            self.retryCount++;
        }
    } else {
        // Retry if there's a connectivity error, otherwise stop polling
        if (error && (error.code == kCFURLErrorNotConnectedToInternet ||
                      error.code == kCFURLErrorNetworkConnectionLost)) {
            [self pollAfter:self.pollInterval];
        } else {
            self.completion(self.latestSource, error);
            [self stopPolling];
        }
    }
}

- (BOOL)shouldContinuePollingSource:(nullable STPSource *)source {
    if (!source) {
        return NO;
    }
    return source.status == STPSourceStatusPending;
}

- (void)stopPolling {
    if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
    }
    if (self.dataTask) {
        [self.dataTask cancel];
        self.dataTask = nil;
    }
}

@end

NS_ASSUME_NONNULL_END
