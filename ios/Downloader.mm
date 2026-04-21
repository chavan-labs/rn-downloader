#import <Foundation/Foundation.h>
#import <React/RCTLog.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>

// ─── Foreground session delegate ──────────────────────────────────────────────
@interface Downloader () <NSURLSessionDownloadDelegate, UIDocumentInteractionControllerDelegate>
@property (nonatomic, strong) NSURLSession *fgSession;       // foreground
@property (nonatomic, strong) NSURLSession *bgSession;       // background
// downloadId → resolve/reject blocks
@property (nonatomic, strong) NSMutableDictionary *activePromises;
// downloadId → original options dict
@property (nonatomic, strong) NSMutableDictionary *downloadOptions;
// downloadId → NSURLSessionDownloadTask
@property (nonatomic, strong) NSMutableDictionary *activeTasks;
// downloadId → NSData (resume data for paused tasks)
@property (nonatomic, strong) NSMutableDictionary *resumeDataStore;
// NSURLSessionTask identifier (int) → downloadId (string)
@property (nonatomic, strong) NSMutableDictionary *taskIdMap;
@end

@implementation Downloader

RCT_EXPORT_MODULE()

- (instancetype)init {
    if (self = [super init]) {
        self.activePromises  = [NSMutableDictionary new];
        self.downloadOptions = [NSMutableDictionary new];
        self.activeTasks     = [NSMutableDictionary new];
        self.resumeDataStore = [NSMutableDictionary new];
        self.taskIdMap       = [NSMutableDictionary new];

        // Foreground session
        NSURLSessionConfiguration *fgConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        self.fgSession = [NSURLSession sessionWithConfiguration:fgConfig delegate:self delegateQueue:nil];

        // Background session (survives app suspension)
        NSURLSessionConfiguration *bgConfig =
            [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"com.downloader.background"];
        bgConfig.discretionary = NO;
        bgConfig.sessionSendsLaunchEvents = YES;
        self.bgSession = [NSURLSession sessionWithConfiguration:bgConfig delegate:self delegateQueue:nil];
    }
    return self;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"onDownloadProgress", @"onDownloadComplete", @"onDownloadError", @"onUploadProgress"];
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

- (NSString *)generateDownloadId {
    return [[NSUUID UUID] UUIDString];
}

- (NSURL *)destURLForFileName:(NSString *)fileName destination:(NSString *)destType {
    NSSearchPathDirectory dirType = NSDownloadsDirectory;
    if ([destType isEqualToString:@"cache"]) {
        dirType = NSCachesDirectory;
    } else if ([destType isEqualToString:@"documents"]) {
        dirType = NSDocumentDirectory;
    }

    NSURL *dirURL = [[NSFileManager defaultManager]
        URLsForDirectory:dirType inDomains:NSUserDomainMask].firstObject;
    
    // For iOS < 16 some directories might not exist or need subfolders
    if ([destType isEqualToString:@"downloads"] && !dirURL) {
        NSURL *docsDir = [[NSFileManager defaultManager]
            URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        dirURL = [docsDir URLByAppendingPathComponent:@"Downloads"];
        [[NSFileManager defaultManager] createDirectoryAtURL:dirURL withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return [dirURL URLByAppendingPathComponent:fileName];
}

- (NSString *)calculateChecksumForPath:(NSString *)path algorithm:(NSString *)algo {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if ([algo isEqualToString:@"MD5"]) {
        CC_MD5(data.bytes, (CC_LONG)data.length, digest);
        NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
        for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [output appendFormat:@"%02x", digest[i]];
        return output;
    } else if ([algo isEqualToString:@"SHA1"]) {
        CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
        NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [output appendFormat:@"%02x", digest[i]];
        return output;
    } else {
        CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
        NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
        for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [output appendFormat:@"%02x", digest[i]];
        return output;
    }
}

- (NSString *)fileNameFromOptions:(NSDictionary *)options task:(NSURLSessionDownloadTask *)task {
    NSString *name = options[@"fileName"];
    if (!name || [name isEqualToString:@""]) {
        name = task.originalRequest.URL.lastPathComponent;
    }
    if (!name || [name isEqualToString:@""]) {
        name = @"downloaded_file";
    }
    return name;
}

// ─── download ─────────────────────────────────────────────────────────────────

- (void)download:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    NSString *urlString = options[@"url"];
    if (!urlString) {
        resolve(@{@"success": @NO, @"error": @"URL is missing"});
        return;
    }

    BOOL isBackground = [options[@"background"] boolValue];
    NSString *downloadId = [self generateDownloadId];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    // Add custom headers
    NSDictionary *headers = options[@"headers"];
    if (headers) {
        for (NSString *key in headers) {
            [request setValue:headers[key] forHTTPHeaderField:key];
        }
    }

    NSURLSession *session = isBackground ? self.bgSession : self.fgSession;
    NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:request];
    NSString *taskKey = [NSString stringWithFormat:@"%lu", (unsigned long)task.taskIdentifier];

    self.taskIdMap[taskKey]       = downloadId;
    self.activeTasks[downloadId]  = task;
    self.downloadOptions[downloadId] = options;
    task.taskDescription = downloadId;

    if (isBackground) {
        // Resolve immediately with the downloadId — result comes via event
        resolve(@{@"success": @YES, @"downloadId": downloadId});
    } else {
        self.activePromises[downloadId] = @{@"resolve": resolve, @"reject": reject};
    }

    [task resume];
}

// ─── pauseDownload ────────────────────────────────────────────────────────────

- (void)pauseDownload:(NSString *)downloadId resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    NSURLSessionDownloadTask *task = self.activeTasks[downloadId];
    if (!task) {
        resolve(@{@"success": @NO, @"error": @"Download not found"});
        return;
    }

    [task cancelByProducingResumeData:^(NSData *resumeData) {
        if (resumeData) {
            self.resumeDataStore[downloadId] = resumeData;
        }
        [self.activeTasks removeObjectForKey:downloadId];
        resolve(@{@"success": @YES});
    }];
}

// ─── resumeDownload ───────────────────────────────────────────────────────────

- (void)resumeDownload:(NSString *)downloadId resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    NSData *resumeData = self.resumeDataStore[downloadId];
    if (!resumeData) {
        resolve(@{@"success": @NO, @"error": @"No resume data — download was not paused or was cancelled"});
        return;
    }

    NSDictionary *options = self.downloadOptions[downloadId];
    BOOL isBackground = [options[@"background"] boolValue];
    NSURLSession *session = isBackground ? self.bgSession : self.fgSession;

    NSURLSessionDownloadTask *task = [session downloadTaskWithResumeData:resumeData];
    NSString *taskKey = [NSString stringWithFormat:@"%lu", (unsigned long)task.taskIdentifier];

    self.taskIdMap[taskKey]      = downloadId;
    self.activeTasks[downloadId] = task;
    [self.resumeDataStore removeObjectForKey:downloadId];

    [task resume];
    resolve(@{@"success": @YES});
}

// ─── cancelDownload ───────────────────────────────────────────────────────────

- (void)cancelDownload:(NSString *)downloadId resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    NSURLSessionDownloadTask *task = self.activeTasks[downloadId];
    if (task) {
        [task cancel];
        [self.activeTasks removeObjectForKey:downloadId];
    }
    [self.resumeDataStore removeObjectForKey:downloadId];
    [self.activePromises removeObjectForKey:downloadId];
    [self.downloadOptions removeObjectForKey:downloadId];
    resolve(@{@"success": @YES});
}

// ─── getCachedFiles ───────────────────────────────────────────────────────────

- (void)getCachedFiles:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    NSURL *downloadsDir = [[NSFileManager defaultManager]
        URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    if (!downloadsDir) {
        // Fallback for iOS < 16
        NSURL *docsDir = [[NSFileManager defaultManager]
            URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        downloadsDir = [docsDir URLByAppendingPathComponent:@"Downloads"];
    }

    NSError *error;
    NSArray<NSURL *> *files = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:downloadsDir
        includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles
        error:&error];

    if (error) {
        resolve(@{@"success": @NO, @"error": error.localizedDescription});
        return;
    }

    NSMutableArray *result = [NSMutableArray new];
    for (NSURL *fileURL in files) {
        NSNumber *size;
        NSDate *modDate;
        [fileURL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        [fileURL getResourceValue:&modDate forKey:NSURLContentModificationDateKey error:nil];
        [result addObject:@{
            @"fileName": fileURL.lastPathComponent,
            @"filePath": fileURL.path,
            @"size":     size ?: @0,
            @"modifiedAt": @((long long)([modDate timeIntervalSince1970] * 1000))
        }];
    }

    resolve(@{@"success": @YES, @"files": result});
}

// ─── deleteFile ───────────────────────────────────────────────────────────────

- (void)deleteFile:(NSString *)filePath resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (error) {
        resolve(@{@"success": @NO, @"error": error.localizedDescription});
    } else {
        resolve(@{@"success": @YES});
    }
}

// ─── clearCache ───────────────────────────────────────────────────────────────

- (void)clearCache:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    NSURL *downloadsDir = [[NSFileManager defaultManager]
        URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    if (!downloadsDir) {
        // Fallback for iOS < 16
        NSURL *docsDir = [[NSFileManager defaultManager]
            URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        downloadsDir = [docsDir URLByAppendingPathComponent:@"Downloads"];
    }

    NSError *error;
    NSArray<NSURL *> *files = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:downloadsDir
        includingPropertiesForKeys:nil
        options:NSDirectoryEnumerationSkipsHiddenFiles
        error:&error];

    if (error) {
        resolve(@{@"success": @NO, @"error": error.localizedDescription});
        return;
    }

    for (NSURL *fileURL in files) {
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
    }
    resolve(@{@"success": @YES});
}

// ─── getBackgroundDownloads ───────────────────────────────────────────────────

- (void)getBackgroundDownloads:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    [self.bgSession getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        NSMutableArray *results = [NSMutableArray new];
        for (NSURLSessionDownloadTask *task in downloadTasks) {
            NSString *downloadId = task.taskDescription ?: @"";
            NSString *url = task.originalRequest.URL.absoluteString ?: @"";
            
            int progress = 0;
            if (task.countOfBytesExpectedToReceive > 0) {
                progress = (int)((task.countOfBytesReceived * 100) / task.countOfBytesExpectedToReceive);
            }
            
            [results addObject:@{
                @"downloadId": downloadId,
                @"url": url,
                @"status": @(task.state), // 0=Running, 1=Suspended, 2=Canceling, 3=Completed
                @"progress": @(progress)
            }];
        }
        resolve(@{@"success": @YES, @"downloads": results});
    }];
}

// ─── NSURLSession delegates ───────────────────────────────────────────────────

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite > 0) {
        int progress = (int)((totalBytesWritten * 100) / totalBytesExpectedToWrite);
        NSString *taskKey = [NSString stringWithFormat:@"%lu", (unsigned long)downloadTask.taskIdentifier];
        NSString *downloadId = self.taskIdMap[taskKey] ?: @"";
        NSString *url = downloadTask.originalRequest.URL.absoluteString ?: @"";

        [self sendEventWithName:@"onDownloadProgress"
                           body:@{@"url": url, @"downloadId": downloadId, @"progress": @(progress)}];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSString *taskKey = [NSString stringWithFormat:@"%lu", (unsigned long)downloadTask.taskIdentifier];
    NSString *downloadId = self.taskIdMap[taskKey];
    if (!downloadId) return;

    NSDictionary *options = self.downloadOptions[downloadId];
    NSString *fileName = [self fileNameFromOptions:options task:downloadTask];
    NSString *destType = options[@"destination"] ?: @"downloads";
    NSURL *destURL = [self destURLForFileName:fileName destination:destType];

    NSError *error;
    [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:destURL error:&error];

    NSDictionary *resultDict;
    if (error) {
        resultDict = @{@"success": @NO, @"downloadId": downloadId, @"error": error.localizedDescription};
    } else {
        // Checksum verification
        NSDictionary *checksum = options[@"checksum"];
        if (checksum) {
            NSString *expectedHash = checksum[@"hash"];
            NSString *algo = checksum[@"algorithm"] ?: @"MD5";
            NSString *actualHash = [self calculateChecksumForPath:destURL.path algorithm:algo.uppercaseString];
            if (![actualHash.lowercaseString isEqualToString:expectedHash.lowercaseString]) {
                [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
                resultDict = @{
                    @"success": @NO,
                    @"downloadId": downloadId,
                    @"error": [NSString stringWithFormat:@"CHECKSUM_MISMATCH: expected %@, got %@", expectedHash, actualHash]
                };
            } else {
                resultDict = @{@"success": @YES, @"downloadId": downloadId, @"filePath": destURL.path};
            }
        } else {
            resultDict = @{@"success": @YES, @"downloadId": downloadId, @"filePath": destURL.path};
        }
    }

    NSDictionary *funcs = self.activePromises[downloadId];
    BOOL isBackground = [options[@"background"] boolValue];

    if (funcs && !isBackground) {
        // Foreground: resolve the promise
        RCTPromiseResolveBlock resolve = funcs[@"resolve"];
        resolve(resultDict);
    } else {
        // Background: fire event
        NSString *event = error ? @"onDownloadError" : @"onDownloadComplete";
        [self sendEventWithName:event body:resultDict];
    }

    [self.activePromises  removeObjectForKey:downloadId];
    [self.downloadOptions removeObjectForKey:downloadId];
    [self.activeTasks     removeObjectForKey:downloadId];
    [self.taskIdMap       removeObjectForKey:taskKey];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (!error) return;
    // Ignore cancellation
    if (error.code == NSURLErrorCancelled) return;

    NSString *taskKey = [NSString stringWithFormat:@"%lu", (unsigned long)task.taskIdentifier];
    NSString *downloadId = self.taskIdMap[taskKey];
    if (!downloadId) return;

    NSDictionary *options = self.downloadOptions[downloadId];
    BOOL isBackground = [options[@"background"] boolValue];

    NSDictionary *errDict = @{@"success": @NO, @"downloadId": downloadId, @"error": error.localizedDescription};

    NSDictionary *funcs = self.activePromises[downloadId];
    if (funcs && !isBackground) {
        RCTPromiseResolveBlock resolve = funcs[@"resolve"];
        resolve(errDict);
    } else {
        [self sendEventWithName:@"onDownloadError" body:errDict];
    }

    [self.activePromises  removeObjectForKey:downloadId];
    [self.downloadOptions removeObjectForKey:downloadId];
    [self.activeTasks     removeObjectForKey:downloadId];
    [self.taskIdMap       removeObjectForKey:taskKey];
}

// ─── TurboModule ──────────────────────────────────────────────────────────────

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeDownloaderSpecJSI>(params);
}

+ (NSString *)moduleName
{
  return @"Downloader";
}

// ─── upload ───────────────────────────────────────────────────────────────────

- (void)upload:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    NSString *urlString = options[@"url"];
    NSString *filePath  = options[@"filePath"];
    if (!urlString || !filePath) {
        resolve(@{@"success": @NO, @"error": @"URL or filePath is missing"});
        return;
    }

    NSString *fieldName = options[@"fieldName"] ?: @"file";
    NSDictionary *headers = options[@"headers"];
    NSDictionary *params  = options[@"parameters"];
    
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    
    if (headers) {
        for (NSString *key in headers) {
            [request setValue:headers[key] forHTTPHeaderField:key];
        }
    }

    NSMutableData *body = [NSMutableData data];
    [params enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@\r\n", value] dataUsingEncoding:NSUTF8StringEncoding]];
    }];

    NSString *fileName = [filePath lastPathComponent];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", fieldName, fileName] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[NSData dataWithContentsOfFile:filePath]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    NSURLSessionUploadTask *task = [[NSURLSession sharedSession] uploadTaskWithRequest:request fromData:body completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            resolve(@{@"success": @NO, @"error": error.localizedDescription});
        } else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSString *respData = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            resolve(@{
                @"success": @(httpResponse.statusCode >= 200 && httpResponse.statusCode < 300),
                @"status": @(httpResponse.statusCode),
                @"data": respData ?: @""
            });
        }
    }];
    
    // Note: URLSessionUploadTask doesn't have a simple progress delegate for fromData: uploads without using a delegate-based session.
    // For simplicity in this step, we'll skip progress for now or refactor to delegate later if needed.
    [task resume];
}

// ─── saveBase64AsFile ─────────────────────────────────────────────────────────

RCT_REMAP_METHOD(saveBase64AsFile,
                 base64Options:(NSDictionary *)options
                 saveResolver:(RCTPromiseResolveBlock)resolve
                 saveRejecter:(RCTPromiseRejectBlock)reject)
{
    NSString *base64String = options[@"base64Data"];
    if (!base64String || base64String.length == 0) {
        resolve(@{@"success": @NO, @"error": @"base64Data is required"});
        return;
    }
    
    NSString *fileName = options[@"fileName"];
    if (!fileName || fileName.length == 0) {
        fileName = [NSString stringWithFormat:@"base64_file_%lld", (long long)([[NSDate date] timeIntervalSince1970] * 1000)];
    }
    
    NSString *destination = options[@"destination"] ?: @"downloads";
    
    // Decode base64
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:base64String options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!decodedData) {
        resolve(@{@"success": @NO, @"error": @"Invalid base64 string"});
        return;
    }
    
    NSURL *destURL = [self destURLForFileName:fileName destination:destination];
    NSError *writeError = nil;
    BOOL success = [decodedData writeToURL:destURL options:NSDataWritingAtomic error:&writeError];
    
    if (!success || writeError) {
        resolve(@{@"success": @NO, @"error": writeError ? writeError.localizedDescription : @"Failed to write file"});
        return;
    }
    
    resolve(@{
        @"success": @YES,
        @"filePath": destURL.path
    });
}

// ─── urlToBase64 ──────────────────────────────────────────────────────────────

RCT_REMAP_METHOD(urlToBase64,
                 urlOptions:(NSDictionary *)options
                 urlResolver:(RCTPromiseResolveBlock)resolve
                 urlRejecter:(RCTPromiseRejectBlock)reject)
{
    NSString *urlString = options[@"url"];
    if (!urlString || urlString.length == 0) {
        resolve(@{@"success": @NO, @"error": @"URL is required"});
        return;
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        resolve(@{@"success": @NO, @"error": @"Invalid URL"});
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 30.0;
    
    // Add custom headers if provided
    NSDictionary *headers = options[@"headers"];
    if (headers) {
        for (NSString *key in headers) {
            [request setValue:headers[key] forHTTPHeaderField:key];
        }
    }
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            resolve(@{@"success": @NO, @"error": error.localizedDescription});
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            resolve(@{@"success": @NO, @"error": [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]});
            return;
        }
        
        if (!data || data.length == 0) {
            resolve(@{@"success": @NO, @"error": @"No data received"});
            return;
        }
        
        // Get MIME type from response
        NSString *mimeType = httpResponse.MIMEType ?: @"application/octet-stream";
        
        // Encode to base64
        NSString *base64String = [data base64EncodedStringWithOptions:0];
        NSString *dataUri = [NSString stringWithFormat:@"data:%@;base64,%@", mimeType, base64String];
        
        resolve(@{
            @"success": @YES,
            @"base64": base64String,
            @"mimeType": mimeType,
            @"dataUri": dataUri
        });
    }];
    
    [task resume];
}

// ─── shareFile ────────────────────────────────────────────────────────────────

RCT_REMAP_METHOD(shareFile,
                 shareFilePath:(NSString *)filePath
                 shareOptions:(NSDictionary *)options
                 shareResolver:(RCTPromiseResolveBlock)resolve
                 shareRejecter:(RCTPromiseRejectBlock)reject)
{
    if (!filePath || filePath.length == 0) {
        resolve(@{@"success": @NO, @"error": @"File path is required"});
        return;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        resolve(@{@"success": @NO, @"error": [NSString stringWithFormat:@"File not found: %@", filePath]});
        return;
    }
    
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *rootViewController = [UIApplication sharedApplication].delegate.window.rootViewController;
        
        // Find the topmost view controller
        while (rootViewController.presentedViewController) {
            rootViewController = rootViewController.presentedViewController;
        }
        
        NSArray *itemsToShare = @[fileURL];
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:itemsToShare applicationActivities:nil];
        
        // For iPad, set the popover presentation controller
        if (activityVC.popoverPresentationController) {
            activityVC.popoverPresentationController.sourceView = rootViewController.view;
            activityVC.popoverPresentationController.sourceRect = CGRectMake(rootViewController.view.bounds.size.width / 2,
                                                                              rootViewController.view.bounds.size.height / 2,
                                                                              0, 0);
            activityVC.popoverPresentationController.permittedArrowDirections = 0;
        }
        
        activityVC.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
            if (activityError) {
                resolve(@{@"success": @NO, @"error": activityError.localizedDescription});
            } else {
                resolve(@{@"success": @YES, @"completed": @(completed)});
            }
        };
        
        [rootViewController presentViewController:activityVC animated:YES completion:nil];
    });
}

// ─── openFile ─────────────────────────────────────────────────────────────────

RCT_REMAP_METHOD(openFile,
                 openFilePath:(NSString *)filePath
                 mimeType:(NSString *)mimeType
                 openResolver:(RCTPromiseResolveBlock)resolve
                 openRejecter:(RCTPromiseRejectBlock)reject)
{
    if (!filePath || filePath.length == 0) {
        resolve(@{@"success": @NO, @"error": @"File path is required"});
        return;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        resolve(@{@"success": @NO, @"error": [NSString stringWithFormat:@"File not found: %@", filePath]});
        return;
    }
    
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *rootViewController = [UIApplication sharedApplication].delegate.window.rootViewController;
        
        // Find the topmost view controller
        while (rootViewController.presentedViewController) {
            rootViewController = rootViewController.presentedViewController;
        }
        
        // Use UIDocumentInteractionController for opening files
        UIDocumentInteractionController *documentController = [UIDocumentInteractionController interactionControllerWithURL:fileURL];
        documentController.delegate = (id<UIDocumentInteractionControllerDelegate>)self;
        
        BOOL canOpen = [documentController presentPreviewAnimated:YES];
        
        if (!canOpen) {
            // Fallback: Try to open with options menu
            canOpen = [documentController presentOptionsMenuFromRect:CGRectMake(rootViewController.view.bounds.size.width / 2,
                                                                                 rootViewController.view.bounds.size.height / 2,
                                                                                 0, 0)
                                                              inView:rootViewController.view
                                                            animated:YES];
        }
        
        if (canOpen) {
            resolve(@{@"success": @YES});
        } else {
            resolve(@{@"success": @NO, @"error": @"No app found to open this file"});
        }
    });
}

// UIDocumentInteractionControllerDelegate method
- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    UIViewController *rootViewController = [UIApplication sharedApplication].delegate.window.rootViewController;
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }
    return rootViewController;
}

@end
