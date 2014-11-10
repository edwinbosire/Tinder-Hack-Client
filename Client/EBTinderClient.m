//
//  EBTinderClient.m
//  xinder
//
//  Created by edwin bosire on 06/08/2014.
//  Copyright (c) 2014 Edwin Bosire. All rights reserved.
//

#import "EBTinderClient.h"
#import "User.h"
#import "Photo.h"
#import "User+Extention.h"
#import "Photo+Extention.h"
#import "NSDictionary+extention.h"
#import "EBSetting+Extention.h"
#import "EBSetting.h"
#import "HRAlertView.h"


@interface EBTinderClient ()

@property (nonatomic) User *currentUser;




@end

@implementation EBTinderClient


+ (instancetype)sharedClient{
    
    static id shared = nil;
    if (!shared){
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            shared = [[self alloc] init];
        });
    }
    
    return shared;
    
}

- (instancetype)init{
    
    self = [super init];
    if (self) {
        self.currentUser = [User loggedInUser];
        self.hasReset = NO;
    }
    return self;
}


#pragma mark - Tinder

- (void)authenticateWithTinderCompletion:(AuthenticateBlock)block{
    
    [self tinderAuthentication:^(BOOL success) {
        
        if (self.currentUser.xAuthToken && success) {
            
            NSLog(@"Successfully logged into Tinder");
            if (block) block(YES);
        }
        
    }];
    
}

- (void)tinderAuthentication:(AuthenticateBlock)block{
    
    NSMutableURLRequest *request = [self requestWithExtension:@"auth"];
    
    NSString *params = [NSString stringWithFormat:@"facebook_id=%@&facebook_token=%@", self.currentUser.facebookID, self.currentUser.facebookToken];
    [request setHTTPMethod:@"POST"];
    NSData *post = [params dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:post];
    
    NSLog(@"Facebook params %@", params);
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               
                               NSDictionary *dict;
                              
                               if (data) {
                                   
                                   NSError *error = nil;
                                   dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                               }
                               
                               if (dict && dict[@"token"]) {
                                   self.currentUser.xAuthToken = dict[@"token"];
                                   [self parseUser:self.currentUser fromDictionary:dict[@"user"]];
                                   block(YES);
                                   return;
                               }
                               else if (dict[@"error"]) {
                                   
                                   NSLog(@"failed to log into tinder %@", data);
                                   
                                   HRAlertView *alert = [[HRAlertView alloc] initWithTitle:@"Authentication"
                                                                                   message:@"There is an issue with your login, please try again"
                                                                                  delegate:nil
                                                                         cancelButtonTitle:@"Retry"
                                                                         otherButtonTitles:nil, nil];
                                   [alert showWithCompletion:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                       
                                       dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//                                           [self tinderAuthentication:block];
                                       });
                                       
                                   }];
                                   
                                   if (block) block (NO);
                                   
                               }else if(connectionError){
                                   
                                   NSLog(@"network connection error, failed to authenticate with tinder");
                                   if (block) block (NO);
                                   
                                   HRAlertView *alert = [[HRAlertView alloc] initWithTitle:@"Authentication"
                                                                                   message:@"There is an issue with your login, please check your connection and try again"
                                                                                  delegate:nil
                                                                         cancelButtonTitle:@"Retry"
                                                                         otherButtonTitles:nil, nil];
                                   [alert showWithCompletion:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                       
                                       dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                           [self tinderAuthentication:block];
                                       });
                                       
                                   }];
                                   
                               }
                               
                           }];
}

- (void)recommendationsWithBlock:(Completion)block{
    
    [NSURLConnection sendAsynchronousRequest:[self requestWithExtension:@"user/recs"]
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               
                               NSDictionary *dict;
                               NSDictionary *apiError;
                               if (data) {
                                   NSError *error = nil;
                                   dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                                   apiError = dict[@"error"];
                               }
                               
                               
                               if (data && !apiError) {
                                   
                                   NSArray *recs = dict[@"results"];
                                   NSMutableArray *collection = [NSMutableArray new];
                                   
                                   for (id match in recs) {
                                       
                                       User *recommendation = [User create];
                                       recommendation.mainUser = @NO;
                                       [self parseUser:recommendation fromDictionary:match];
                                       
                                       if (![self.recommendations containsObject:recommendation]) {
                                           [collection addObject:recommendation];

                                       }
                                   }
                                   [self.recommendations addObjectsFromArray:collection];
                                   
                                   [[NSNotificationCenter defaultCenter] postNotificationName:@"newRecommendations" object:nil];
                                   block(self.recommendations, collection.count, connectionError);
                                   
                               }else if (apiError){
                                   
                                   NSError *error = [NSError errorWithDomain:@"Swipr" code:0001 userInfo:@{NSLocalizedDescriptionKey: apiError}];
                                   block (nil, 0 , error);
                               }else {
                                   block (nil, 0, [NSError errorWithDomain:@"Swipr" code:0000 userInfo:@{NSLocalizedDescriptionKey: @"Unknown Error"}]);
                               }
                           }];
    
}

- (void)updateProfile:(void(^)(BOOL success))block {
    
    __block User *currentUser = [User loggedInUser];
    
    NSMutableURLRequest *request = [self requestWithExtension:@"profile"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    NSDictionary *params = @{@"age_filter_min": currentUser.ageFilterMin, @"age_filter_max" : currentUser.ageFilterMax, @"distance_filter" : currentUser.distanceFilter};
    
    NSError *error = nil;
    NSData *jsonParams = [NSJSONSerialization dataWithJSONObject:params options:NSJSONWritingPrettyPrinted error:&error];
    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:jsonParams];
    
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               
                               NSError *error = nil;
                               NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                               
                               if (data) {
                                   
                                   [self parseUser:currentUser fromDictionary:dict];
                                   
                                   [currentUser save];
                                   block(YES);
                                   return;
                               }
                               else if (dict[@"error"]) {
                                   
                                   NSLog(@"failed to log into tinder %@", data);
                                   if (block) block (NO);
                                   
                               }else if(connectionError){
                                   
                                   NSLog(@"network connection error, failed to authenticate with tinder");
                                   if (block) block (NO);
                                   
                                   UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Authentication"
                                                                                   message:connectionError.localizedDescription
                                                                                  delegate:nil
                                                                         cancelButtonTitle:@"OK"
                                                                         otherButtonTitles:nil, nil];
                                   [alert show];
                                   
                               }
                               
                           }];
    
}


- (void)pingCurrentLocation{
    /* Code to ping current location goes 'ere */
}

- (void)likeUser:(User *)user {
    
    [self likeUser:user onCompletion:nil];
}

- (void)likeUser:(User *)user onCompletion:(void(^)(BOOL success))block{
    
    NSString *ext = [@"like/" stringByAppendingString:user.tinderID];
    
    [NSURLConnection sendAsynchronousRequest:[self requestWithExtension:ext]
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               
                               if (data) {
                                   NSError *error = nil;
                                   NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                                   user.liked = [NSNumber numberWithBool:YES];
                                   [self.likedUsers addObject:user];
                                   
                                   id match = dict[@"match"];
                                   if ([match isKindOfClass:[NSDictionary class]]) {
                                       
                                       user.match = @YES;
                                       NSLog(@"you've matched with %@", user.name);
                                       [self performSelectorOnMainThread:@selector(completeLikeUserAction:) withObject:user waitUntilDone:NO];
                                       
                                   }else{
                                       user.match = @NO;

                                   }
                                   if (block) block (YES);
                               }else{
                                   if (block) block (NO);
                               }
                           }];
    
}

- (void)passUser:(User *)user onCompletion:(void(^)(BOOL success))block{
    
    NSString *ext = [@"pass/" stringByAppendingString:user.tinderID];
    
    [NSURLConnection sendAsynchronousRequest:[self requestWithExtension:ext]
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               
                               if (data) {
                                   
                                   if (block) block (YES);
                               }else{
                                   
                                   if (block) block (NO);
                               }
                           }];
    
}

- (void)completeLikeUserAction:(NSDictionary *)user{
    
    [self.matches addObject:user];
}

- (void)parseUser:(User *)user fromDictionary:(NSDictionary *)dict {
    
    user.name = [dict[@"name"] description];
    user.bio = [dict[@"bio"] description];
    user.gender = dict[@"gender"];
    user.tinderID = [dict[@"_id"] description];
//    user.birthDay = [dict[@"birth_date"] description]; /* Parse date here*/
    
    if ([dict[@"discoverable"] description] ) {
        user.discoverable = [dict valueForKey:@"discoverable"];
    }else {
        user.discoverable = [NSNumber numberWithBool:YES];
    }
    
    user.dateCreated = [self dateFromString:[dict[@"create_date"] description]];
    user.dateOfBirth =  [self dateFromString:[dict[@"birth_date"] description]];
    user.lastActive = [self dateFromString: [dict[@"ping_time"] description]];
    
    user.ageFilterMax = [NSNumber numberWithInteger:[[dict[@"age_filter_max"] description] integerValue]];
    user.ageFilterMin = [NSNumber numberWithInteger:[[dict[@"age_filter_min"] description] integerValue]];
    user.distanceFilter = [NSNumber numberWithInteger:[[dict[@"distance_filter"] description] integerValue]];
    //    user.commonLikes = [dict valueForKeyNull:@"common_like_count"];
    //    user.commonFriendsCount = [dict valueForKeyPath:@"<#name#>"];
    //    user.commonFriends = [dict valueForKeyNull:@"<#name#>"];
    
    NSArray *photos = dict[@"photos"];
    NSMutableSet *photoSet = [NSMutableSet new];

    [user removePhotos:user.photos];
    for (id aPhoto in photos) {
        
        NSArray *collection = aPhoto[@"processedFiles"];
        Photo *photo = [self photoFromContainer:[collection firstObject]];
        photo.orderId = @([photos indexOfObject:aPhoto]);
        [photoSet addObject:photo];
    }
    [user addPhotos:photoSet];
    
    //    user.facebookFriends = [dict valueForKeyPath:@"<#name#>"];
    //    user.likes = [dict valueForKeyPath:@"<#name#>"];
    
}

- (Photo *)photoFromContainer:(NSDictionary *)container {
    
    Photo *aPhoto = [Photo create];
    aPhoto.width = container[@"width"];
    aPhoto.height = container[@"height"];
    aPhoto.url = container[@"url"];
    
    return aPhoto;
}

- (NSDate *)dateFromString:(NSString *)date {
    if (!date) {
        return nil;
    }
    //2014-08-31T01:11:59.441Z
    static dispatch_once_t onceToken;
    static NSDateFormatter *dateFormatter;
    
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    });
    
    return [dateFormatter dateFromString:date];
}
- (NSMutableArray *)matches {
   
    if (!_matches) {
        _matches = [NSMutableArray new];
    }
    
    return  _matches;
}

- (NSMutableArray *)recommendations {
    
    if (!_recommendations) {
        _recommendations = [NSMutableArray new];
    }
    
    return _recommendations;
}

- (NSMutableArray *)likedUsers{
    
    if (!_likedUsers) {
        _likedUsers = [NSMutableArray new];
    }
    
    return _likedUsers;
}

#pragma mark - Reset

- (void)resetRecommendations{
    
    [self.recommendations removeAllObjects];
    [self.matches removeAllObjects];
    [self.likedUsers removeAllObjects];
    self.hasReset = YES;
}

#pragma mark - Helper

- (NSMutableURLRequest *)requestWithExtension:(NSString *)ext{
    
    NSURL *url = [NSURL URLWithString:[kBaseURL stringByAppendingString:ext] ];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"en;q=1, fr;q=0.9, de;q=0.8, ja;q=0.7, nl;q=0.6, it;q=0.5" forHTTPHeaderField:@"Accept-Language"];
    [request setValue:@"90" forHTTPHeaderField:@"app-version"];
    [request setValue:@"Tinder/4.0.4 (iPhone; iOS 7.1; Scale/2.00)" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"700001" forHTTPHeaderField:@"os_version" ];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    [request setValue:@"ios" forHTTPHeaderField:@"platform"];
    [request setValue:@"-1963196724" forHTTPHeaderField:@"If-None-Match"];
    [request setValue:@"keep-active" forHTTPHeaderField:@"Connection"];
    [request setValue:@"keep-alive" forHTTPHeaderField:@"Proxy-Connection"];
    [request setValue:@"gzip, deflate" forHTTPHeaderField:@"Accept-Encoding"];
    
    if (self.currentUser.xAuthToken) {
        [request setValue:[NSString stringWithFormat:@"Token token=\"%@\"", self.currentUser.xAuthToken]forHTTPHeaderField:@"Authorization"];
        [request setValue:self.currentUser.xAuthToken forHTTPHeaderField:@"X-Auth-Token"];
    }
    
    return request;
}

@end
