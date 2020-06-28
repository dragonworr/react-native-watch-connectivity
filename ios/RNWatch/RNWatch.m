#import "RNWatch.h"
#import "FileTransferInfo.h"
#import "FileTransferEvent.h"
#import "util.h"

// import RCTConvert.h
#if __has_include("RCTConvert.h")
#import "RCTConvert.h"
#elif __has_include(<React/RCTConvert.h>)

#import <React/RCTConvert.h>

#else
#import "React/RCTConvert.h"
#endif

// import RCTEventDispatcher.h
#if __has_include("RCTEventDispatcher.h")
#import "RCTEventDispatcher.h"
#elif __has_include(<React/RCTEventDispatcher.h>)

#import <React/RCTEventDispatcher.h>

#else
#import "React/RCTEventDispatcher.h"
#endif

static NSString *EVENT_FILE_TRANSFER = @"WatchFileTransfer";
static NSString *EVENT_RECEIVE_MESSAGE = @"WatchReceiveMessage";
static NSString *EVENT_RECEIVE_MESSAGE_DATA = @"WatchReceiveMessageData";
static NSString *EVENT_WATCH_STATE_CHANGED = @"WatchStateChanged";
static NSString *EVENT_ACTIVATION_ERROR = @"WatchActivationError";
static NSString *EVENT_WATCH_REACHABILITY_CHANGED = @"WatchReachabilityChanged";
static NSString *EVENT_WATCH_USER_INFO_RECEIVED = @"WatchUserInfoReceived";
static NSString *EVENT_APPLICATION_CONTEXT_RECEIVED = @"WatchApplicationContextReceived";
static NSString *EVENT_SESSION_DID_DEACTIVATE = @"WatchSessionDidDeactivate";
static NSString *EVENT_SESSION_BECAME_INACTIVE = @"WatchSessionBecameInactive";
static NSString *EVENT_PAIR_STATUS_CHANGED = @"WatchPairStatusChanged";
static NSString *EVENT_INSTALL_STATUS_CHANGED = @"WatchInstallStatusChanged";

static RNWatch *sharedInstance;

@implementation RNWatch

RCT_EXPORT_MODULE()

////////////////////////////////////////////////////////////////////////////////
// Init
////////////////////////////////////////////////////////////////////////////////

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

+ (RNWatch *)sharedInstance {
    return sharedInstance;
}

- (instancetype)init {
    sharedInstance = [super init];
    self.replyHandlers = [NSCache new];
    self.fileTransfers = [NSMutableDictionary new];
    self.queuedUserInfo = [NSMutableDictionary new];

    if ([WCSession isSupported]) {
        WCSession *session = [WCSession defaultSession];
        session.delegate = self;
        self.session = session;
        [self.session activateSession];
        [self.session addObserver:self forKeyPath:@"paired" options:NSKeyValueObservingOptionNew context:nil];
        [self.session addObserver:self forKeyPath:@"watchAppInstalled" options:NSKeyValueObservingOptionNew context:nil];
    }

    return sharedInstance;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[
            EVENT_FILE_TRANSFER,
            EVENT_RECEIVE_MESSAGE,
            EVENT_RECEIVE_MESSAGE_DATA,
            EVENT_WATCH_STATE_CHANGED,
            EVENT_ACTIVATION_ERROR,
            EVENT_WATCH_REACHABILITY_CHANGED,
            EVENT_WATCH_USER_INFO_RECEIVED,
            EVENT_APPLICATION_CONTEXT_RECEIVED,
            EVENT_PAIR_STATUS_CHANGED,
            EVENT_INSTALL_STATUS_CHANGED
    ];
}

////////////////////////////////////////////////////////////////////////////////
// Session State
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(getSessionState:
    (RCTResponseSenderBlock) callback) {
    WCSessionActivationState state = self.session.activationState;
    NSString *stateString = [self _getStateString:state];
    callback(@[stateString]);
}

////////////////////////////////////////////////////////////////////////////////

- (void)sessionWatchStateDidChange:(WCSession *)session {
    WCSessionActivationState state = session.activationState;
    [self _sendStateEvent:state];
}

////////////////////////////////////////////////////////////////////////////////

- (void)               session:(WCSession *)session
activationDidCompleteWithState:(WCSessionActivationState)activationState
                         error:(NSError *)error {
    if (error) {
        [self dispatchEventWithName:EVENT_ACTIVATION_ERROR body:@{@"error": error}];
    }
    [self _sendStateEvent:session.activationState];
}

- (void)sessionDidDeactivate:(WCSession *)session {
    [self dispatchEventWithName:EVENT_SESSION_DID_DEACTIVATE body:@{}];
}

- (void)sessionDidBecomeInactive:(WCSession *)session {
    [self dispatchEventWithName:EVENT_SESSION_BECAME_INACTIVE body:@{}];
}

////////////////////////////////////////////////////////////////////////////////

- (NSString *)_getStateString:(WCSessionActivationState)state {
    NSString *stateString;
    switch (state) {
        case WCSessionActivationStateNotActivated:
            stateString = @"WCSessionActivationStateNotActivated";
            break;
        case WCSessionActivationStateInactive:
            stateString = @"WCSessionActivationStateInactive";
            break;
        case WCSessionActivationStateActivated:
            stateString = @"WCSessionActivationStateActivated";
            break;
    }
    return stateString;
}

////////////////////////////////////////////////////////////////////////////////

- (void)_sendStateEvent:(WCSessionActivationState)state {
    NSString *stateString = [self _getStateString:state];
    [self dispatchEventWithName:EVENT_WATCH_STATE_CHANGED body:@{@"state": stateString}];
}

////////////////////////////////////////////////////////////////////////////////
// Complication User Info
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(transferCurrentComplicationUserInfo:
    (NSDictionary<NSString *, id> *) userInfo) {
    [self.session transferCurrentComplicationUserInfo:userInfo];
}



////////////////////////////////////////////////////////////////////////////////
// Reachability
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(getReachability:
    (RCTResponseSenderBlock) callback) {
    callback(@[@(self.session.reachable)]);
}

////////////////////////////////////////////////////////////////////////////////

- (void)sessionReachabilityDidChange:(WCSession *)session {
    BOOL reachable = session.reachable;
    [self dispatchEventWithName:EVENT_WATCH_REACHABILITY_CHANGED body:@{@"reachability": @(reachable)}];
}

////////////////////////////////////////////////////////////////////////////////
// isPaired
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(getIsPaired:
    (RCTResponseSenderBlock) callback) {
    callback(@[@(self.session.isPaired)]);
}

////////////////////////////////////////////////////////////////////////////////
// isWatchAppInstalled
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(getIsWatchAppInstalled:
    (RCTResponseSenderBlock) callback) {
    callback(@[@(self.session.isWatchAppInstalled)]);
}

////////////////////////////////////////////////////////////////////////////////
// Messages
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(sendMessage:
    (NSDictionary *) message
            reply:
            (RCTResponseSenderBlock) replyCallback
            error:
            (RCTResponseErrorBlock) errorCallback) {
    __block BOOL replied = false;
    [self.session
            sendMessage:message
           replyHandler:^(NSDictionary<NSString *, id> *_Nonnull replyMessage) {
               if (!replied) { // prevent Illegal callback invocation
                   replyCallback(@[replyMessage]);
                   replied = true;
               }
           }
           errorHandler:^(NSError *_Nonnull error) {
               if (!replied) { // prevent Illegal callback invocation
                   errorCallback(error);
                   replied = true;
               }
           }
    ];
}

////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(replyToMessageWithId:
    (NSString *) messageId
            withMessage:
            (NSDictionary<NSString *, id> *) message) {
    void (^replyHandler)(NSDictionary<NSString *, id> *_Nonnull)
    = [self.replyHandlers objectForKey:messageId];
    replyHandler(message);
}

////////////////////////////////////////////////////////////////////////////////

- (void)  session:(WCSession *)session
didReceiveMessage:(NSDictionary<NSString *, id> *)message {
    [self dispatchEventWithName:EVENT_RECEIVE_MESSAGE body:message];
}

////////////////////////////////////////////////////////////////////////////////

- (void)  session:(WCSession *)session
didReceiveMessage:(NSDictionary<NSString *, id> *)message
     replyHandler:(void (^)(NSDictionary<NSString *, id> *_Nonnull))replyHandler {
    NSString *messageId = uuid();
    NSMutableDictionary *mutableMessage = [message mutableCopy];
    mutableMessage[@"id"] = messageId;
    [self.replyHandlers setObject:replyHandler forKey:messageId];
    [self dispatchEventWithName:EVENT_RECEIVE_MESSAGE body:mutableMessage];
}

////////////////////////////////////////////////////////////////////////////////
// Message Data
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(sendMessageData:
    (NSString *) str
            encoding:
            (nonnull NSNumber*)encoding
        replyCallback:(RCTResponseSenderBlock)replyCallback
        error:(RCTResponseErrorBlock) errorCallback) {
    NSData *data = [str dataUsingEncoding:(NSStringEncoding) [encoding integerValue]];
    [self.session sendMessageData:data replyHandler:^(NSData *_Nonnull replyMessageData) {
        NSString *responseData = [replyMessageData base64EncodedStringWithOptions:0];
        replyCallback(@[responseData]);
    }                errorHandler:^(NSError *_Nonnull error) {
        errorCallback(error);
    }];
}

////////////////////////////////////////////////////////////////////////////////

- (void)      session:(WCSession *)session
didReceiveMessageData:(NSData *)messageData
         replyHandler:(void (^)(NSData *_Nonnull))replyHandler {
    [self dispatchEventWithName:EVENT_RECEIVE_MESSAGE_DATA body:@{@"data": messageData}];
}

////////////////////////////////////////////////////////////////////////////////
// Files
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(transferFile:
    (NSString *) url
            metaData:
            (nullable NSDictionary<NSString *, id> *)metaData
        callback:(RCTResponseSenderBlock) callback) {
    double startTime = jsTimestamp();

    NSMutableDictionary *mutableMetaData;
    if (metaData) {
        mutableMetaData = [metaData mutableCopy];
    } else {
        mutableMetaData = [NSMutableDictionary new];
    }
    NSString *id = uuid();
    mutableMetaData[@"id"] = id;
    WCSessionFileTransfer *transfer = [self.session transferFile:[NSURL URLWithString:url] metadata:mutableMetaData];

    [self initialiseTransferInfoWithURL:url metaData:metaData startTime:startTime id:id transfer:transfer];

    FileTransferEvent *event = [self getFileTransferEvent:transfer];

    [self dispatchEventWithName:EVENT_FILE_TRANSFER body:[event serializeWithEventType:FILE_EVENT_STARTED]];

    callback(@[id]);
}

- (void)initialiseTransferInfoWithURL:(NSString *)url metaData:(NSDictionary *)metaData startTime:(double)startTime id:(NSString *)id transfer:(WCSessionFileTransfer *)transfer {
    FileTransferInfo *info = [FileTransferInfo new];

    info.transfer = transfer;
    info.id = id;
    info.uri = url;
    info.metaData = metaData;
    info.startTime = @(startTime);

    self.fileTransfers[id] = info;

    [self observeTransferProgress:transfer];
}

- (void)observeTransferProgress:(WCSessionFileTransfer *)transfer {
    [transfer addObserver:self forKeyPath:@"progress.fractionCompleted" options:NSKeyValueObservingOptionNew context:nil];
    [transfer addObserver:self forKeyPath:@"progress.completedUnitCount" options:NSKeyValueObservingOptionNew context:nil];
    [transfer addObserver:self forKeyPath:@"progress.estimatedTimeRemaining" options:NSKeyValueObservingOptionNew context:nil];
    [transfer addObserver:self forKeyPath:@"progress.throughput" options:NSKeyValueObservingOptionNew context:nil];
}

RCT_EXPORT_METHOD(getFileTransfers:
    (RCTResponseSenderBlock) callback) {
    NSMutableDictionary *transfers = self.fileTransfers;
    NSMutableDictionary *payload = [NSMutableDictionary new];

    for (NSString *transferId in transfers) {
        FileTransferInfo *transferInfo = transfers[transferId];
        WCSessionFileTransfer *fileTransfer = transferInfo.transfer;
        FileTransferEvent *event = [self getFileTransferEvent:fileTransfer];
        payload[transferId] = [event serialize];
    }

    callback(@[payload]);
}

- (FileTransferEvent *)getFileTransferEvent:(WCSessionFileTransfer *)transfer {
    NSString *uuid = transfer.file.metadata[@"id"];

    FileTransferInfo *transferInfo = self.fileTransfers[uuid];

    NSNumber *_Nonnull completedUnitCount = @(transfer.progress.completedUnitCount);

    NS_REFINED_FOR_SWIFT NSNumber *estimatedTimeRemaining = transfer.progress.estimatedTimeRemaining;

    NSNumber *_Nonnull fractionCompleted = @(transfer.progress.fractionCompleted);

    NS_REFINED_FOR_SWIFT NSNumber *throughput = transfer.progress.throughput;

    NSNumber *_Nonnull totalUnitCount = @(transfer.progress.totalUnitCount);

    FileTransferEvent * event = [[FileTransferEvent alloc] initWithTransferInfo:transferInfo];

    event.bytesTransferred = completedUnitCount;
    event.estimatedTimeRemaining = estimatedTimeRemaining;
    event.id = uuid;
    event.fractionCompleted = fractionCompleted;
    event.throughput = throughput;
    event.bytesTotal = totalUnitCount;

    return event;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if ([keyPath hasPrefix:@"progress"]) {
        WCSessionFileTransfer *transfer = object;
        FileTransferEvent *event = [self getFileTransferEvent:transfer];
        [self dispatchEventWithName:EVENT_FILE_TRANSFER body:[event serializeWithEventType:FILE_EVENT_PROGRESS]];
    } else if ([keyPath isEqualToString:@"paired"]) {
        [self dispatchEventWithName:EVENT_PAIR_STATUS_CHANGED body:@{@"paired": change[NSKeyValueChangeNewKey]}];
    } else if ([keyPath isEqualToString:@"watchAppInstalled"]) {
        [self dispatchEventWithName:EVENT_INSTALL_STATUS_CHANGED body:@{@"installed": change[NSKeyValueChangeNewKey]}];
    }
}

- (void)session:(WCSession *)session
 didReceiveFile:(WCSessionFile *)file {
    // TODO
}

- (void)      session:(WCSession *)session
didFinishFileTransfer:(WCSessionFileTransfer *)fileTransfer
                error:(NSError *)error {
    double endTime = jsTimestamp();

    WCSessionFile *file = fileTransfer.file;
    NSDictionary<NSString *, id> *metadata = file.metadata;
    NSString *transferId = metadata[@"id"];
    if (transferId) {
        FileTransferInfo *transferInfo = self.fileTransfers[transferId];

        transferInfo.endTime = @(endTime);

        if (transferInfo) {
            if (error) {
                transferInfo.error = error;
                FileTransferEvent *event = [self getFileTransferEvent:fileTransfer];
                [self dispatchEventWithName:EVENT_FILE_TRANSFER
                                       body:[event serializeWithEventType:FILE_EVENT_ERROR]];
            } else {
                FileTransferEvent *event = [self getFileTransferEvent:fileTransfer];
                [self dispatchEventWithName:EVENT_FILE_TRANSFER body:[event serializeWithEventType:FILE_EVENT_FINISHED]];
            }

            WCSessionFileTransfer *transfer = transferInfo.transfer;
            [transfer removeObserver:self forKeyPath:@"progress.fractionCompleted"];
            [transfer removeObserver:self forKeyPath:@"progress.completedUnitCount"];
            [transfer removeObserver:self forKeyPath:@"progress.estimatedTimeRemaining"];
            [transfer removeObserver:self forKeyPath:@"progress.throughput"];
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
// Context
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(updateApplicationContext:
    (NSDictionary<NSString *, id> *) context) {
    [self.session updateApplicationContext:context error:nil];
}

////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(getApplicationContext:
    (RCTResponseSenderBlock) callback) {
    NSDictionary<NSString *, id> *applicationContext = self.session.applicationContext;
    if (applicationContext == nil) {
        callback(@[[NSNull null]]);
    } else {
        callback(@[applicationContext]);
    }
}

////////////////////////////////////////////////////////////////////////////////

- (void)             session:(WCSession *)session
didReceiveApplicationContext:(NSDictionary<NSString *, id> *)applicationContext {
    [self.session updateApplicationContext:applicationContext error:nil];
    [self dispatchEventWithName:EVENT_APPLICATION_CONTEXT_RECEIVED body:applicationContext];
}

////////////////////////////////////////////////////////////////////////////////
// User Info
////////////////////////////////////////////////////////////////////////////////

RCT_EXPORT_METHOD(getQueuedUserInfo:
    (RCTResponseSenderBlock) callback) {
    callback(@[self.queuedUserInfo]);
    // Clear the cache.
    self.queuedUserInfo = [NSMutableDictionary new];
}

RCT_EXPORT_METHOD(transferUserInfo:
    (NSDictionary<NSString *, id> *) userInfo) {
    [self.session transferUserInfo:userInfo];
}

RCT_EXPORT_METHOD(clearUserInfoQueue:
    (RCTResponseSenderBlock) callback) {
    self.queuedUserInfo = [NSMutableDictionary new];
    callback(@[]);
}

RCT_EXPORT_METHOD(dequeueUserInfo:
    (NSArray<NSString *> *) ids withCallback:
    (RCTResponseSenderBlock) callback) {
    for (NSString *ident in ids) {
        [self.queuedUserInfo removeObjectForKey:ident];
    }
    [self dispatchEventWithName:EVENT_WATCH_USER_INFO_RECEIVED body:self.queuedUserInfo];
    callback(@[self.queuedUserInfo]);
}

- (void)session:(WCSession *)session didFinishUserInfoTransfer:(WCSessionUserInfoTransfer *)userInfoTransfer error:(NSError *)error {
    // TODO
}

- (void)   session:(WCSession *)session
didReceiveUserInfo:(NSDictionary<NSString *, id> *)userInfo {
    double ts = jsTimestamp();
    NSString *timestamp = [@(ts) stringValue];
    [self.queuedUserInfo setValue:userInfo forKey:timestamp];
    [self dispatchEventWithName:EVENT_WATCH_USER_INFO_RECEIVED body:@{@"userInfo": userInfo, @"timestamp": @(ts), @"id": timestamp}];
}

////////////////////////////////////////////////////////////////////////////////
// Events
////////////////////////////////////////////////////////////////////////////////

- (void)dispatchEventWithName:(NSString *)name
                         body:(NSDictionary<NSString *, id> *)body {
    [self sendEventWithName:name body:body];
}

@end
