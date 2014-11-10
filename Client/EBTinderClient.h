//
//  EBTinderClient.h
//  xinder
//
//  Created by edwin bosire on 06/08/2014.
//  Copyright (c) 2014 Edwin Bosire. All rights reserved.
//

/*
 This is the client I am using on my tinder hack app, its not perfect, it was written in shorter than the time it takes you to eat a burrito.
 */

#import <Foundation/Foundation.h>

#define kBaseURL @"https://api.gotinder.com/"

@class User;

typedef void (^Completion)(NSArray *recommendations, NSInteger count, NSError *connectionError);
typedef void (^UserCompletion)(User *user, NSError *connectionError);
typedef void(^AuthenticateBlock)(BOOL success);



@interface EBTinderClient : NSObject

@property (nonatomic, strong) AuthenticateBlock authenticateBlock;

@property (nonatomic) __block NSMutableArray *likedUsers;
@property (nonatomic) __block NSMutableArray *matches;
@property (nonatomic) NSMutableArray *recommendations;
@property (nonatomic) BOOL hasReset;

/* Singleton init */
+ (instancetype)sharedClient;

- (void)authenticateWithTinderCompletion:(AuthenticateBlock)block;

- (void)recommendationsWithBlock:(Completion)block;

- (void)pingCurrentLocation;

- (void)likeUser:(User *)user;

- (void)likeUser:(User *)user onCompletion:(void(^)(BOOL success))block;

- (void)passUser:(User *)user onCompletion:(void(^)(BOOL success))block;

- (void)updateProfile:(void(^)(BOOL success))block;

- (void)resetRecommendations;
@end
