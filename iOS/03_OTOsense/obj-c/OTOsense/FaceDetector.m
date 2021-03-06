//
//  FaceDetector.m
//  OTOsense
//
//  Created by 昭宏 上原 on 12/06/19.
//  Copyright (c) 2012年 REINFORCE Lab. All rights reserved.
//

#import "FaceDetector.h"
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>

@interface FaceDetector() {
    NSArray *features_;
    UIView *previewView_;
    AVCaptureSession *session_;
    AVCaptureVideoPreviewLayer *preview_;
    AVCaptureVideoDataOutput *videoOutput_;
    CIDetector *faceDetector_;
    CALayer *layer_;
    
    int imageOrientation_;
}

@property (assign, nonatomic) BOOL isCameraAvailable;

- (void)initVideoSession;
- (void)didRotate:(NSNotification*)notification;
- (void)updateDeviceRotation:(UIDeviceOrientation)orientation;
@end

@implementation FaceDetector
@synthesize isCameraAvailable;
@synthesize delegate;
#pragma mark - constructor
-(id)initWithView:(UIView *)preview
{
    self = [super init];
    if(self) {
        [self initVideoSession];
        
        previewView_ = preview;
        faceDetector_ = [CIDetector
                         detectorOfType:CIDetectorTypeFace context:nil
                         options:[NSDictionary dictionaryWithObject:CIDetectorAccuracyLow forKey:CIDetectorAccuracy]];
        
        //    CIDetector* detector = [CIDetector detectorOfType:CIDetectorTypeFace
        //                            context:nil options:[NSDictionary dictionaryWithObject:CIDetectorAccuracyHigh forKey:CIDetectorAccuracy]];
        // adding camera preview layer
        preview_ = [AVCaptureVideoPreviewLayer layerWithSession:session_];
        preview_.frame = previewView_.bounds;
        [previewView_.layer addSublayer:preview_];
        
        // add sublayer
        layer_ = [CALayer layer];
        layer_.delegate = self;
        layer_.frame = previewView_.bounds;
        layer_.contentsScale = [[UIScreen mainScreen] scale];
        [previewView_.layer addSublayer:layer_];
        
        
        // 回転方向通知、登録
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didRotate:) name:UIDeviceOrientationDidChangeNotification object:nil];
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    }
    return self;
}
-(void)dealloc
{
    [self stop];
    
    // 回転方向通知、登録削除
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    previewView_ = nil;
    session_     = nil;
    preview_     = nil;
    videoOutput_ = nil;
    layer_       = nil;
}

#pragma mark - Private methods
- (void)didRotate:(NSNotification*)notification
{
    [self updateDeviceRotation:[UIDevice currentDevice].orientation];
}
- (void)updateDeviceRotation:(UIDeviceOrientation)orientation
{
    /*
     Value Location of the origin of the image
     1 Top, left
     2 Top, right
     3 Bottom, right
     4 Bottom, left
     5 Left, top
     6 Right, top
     7 Right, bottom
     8 Left, bottom
     */
    AVCaptureVideoOrientation videoOrietantion;
    imageOrientation_ = 1;
    switch (orientation) {
        case UIDeviceOrientationPortraitUpsideDown:
            videoOrietantion = AVCaptureVideoOrientationPortraitUpsideDown;
            
            break;
            
        case UIDeviceOrientationPortrait:
        default:
            videoOrietantion = AVCaptureVideoOrientationPortrait;
            
            break;
    }
    
    [preview_ setOrientation:videoOrietantion];
    AVCaptureConnection *videoConnectin = [videoOutput_ connectionWithMediaType:AVMediaTypeVideo];
    if([videoConnectin isVideoOrientationSupported]) {
        [videoConnectin setVideoOrientation:videoOrietantion] ;
    }
}

- (void)initVideoSession {
    NSError *error;
    
    session_ = [AVCaptureSession new];
    [session_ beginConfiguration];
    session_.sessionPreset = AVCaptureSessionPreset640x480;
    //    session_.sessionPreset = AVCaptureSessionPresetHigh;
    
    // setting up vidoe input
    //	AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    //NSLog(@"video device count: %d", [devices count]);
    self.isCameraAvailable = ([devices count] >= 2);
    if( ! self.isCameraAvailable) {
        return;
    }
    
    AVCaptureDevice *videoDevice = [devices objectAtIndex:1];
    
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if(error) {
        NSLog(@"Video input device initialization error. %s, %@",__func__, error);
    }
    [session_ addInput:videoInput];
    
    // setting up video output
    videoOutput_ = [[AVCaptureVideoDataOutput alloc] init];
    // Specify the pixel format
    videoOutput_.videoSettings = [NSDictionary dictionaryWithObject:
                                  [NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    
    // queue for sample buffer callback
    dispatch_queue_t queue = dispatch_queue_create("videoqueue", DISPATCH_QUEUE_SERIAL);
    [videoOutput_ setSampleBufferDelegate:self queue:queue];
    
    dispatch_release(queue);
    videoOutput_.alwaysDiscardsLateVideoFrames = YES; // allow dropping a frame when its disposing time ups, default is YES
    [session_ addOutput:videoOutput_];
    
    [session_ commitConfiguration];
}

-(void)start
{
    if(! self.isCameraAvailable) return;
    
    // starting video session (starting preview)
    [session_ startRunning];
    
    // updating an orientation of the preview layer
    int64_t delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self updateDeviceRotation:[UIDevice currentDevice].orientation];
    });
    
}
-(void)stop
{
    if(! self.isCameraAvailable) return;
    
    [session_ stopRunning];
}
#pragma mark - Private methods
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx
{
    CGContextSaveGState(ctx);
    
    // 描画領域のクリア
	CGContextSetRGBFillColor(ctx,   1.0, 1.0, 1.0, 0.0); // fill clear
	CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.0); // stroke transparent
	CGContextFillRect(ctx, previewView_.bounds);
    
    // 領域の描画
    CGContextSetRGBStrokeColor(ctx, 0, 1.0, 0, 0.8); // stroke green
    CGContextSetLineWidth(ctx, 4);
    for(CIFaceFeature *feature in features_) {
        // 座標変換
        // 顔検出は、640x480 (ホームボタンを右に見て、第1象限。画面縦方向に640)
        // 画面表示領域は、320x411 (UIKitの座標系)
        // なので画面両端に 6px 隙間がある
        // 縮尺率は、0.624
        const float scale = 0.642;
        const CGRect r = feature.bounds;
        CGRect rect = CGRectMake((480 - r.origin.x - r.size.width)  * scale + 6,
                                 (680 - r.origin.y - r.size.height) * scale,
                                 r.size.height *scale,
                                 r.size.width  *scale);
        CGContextStrokeRect(ctx, rect);
        //NSLog(@"%@ bounds:%@", NSStringFromCGRect(rect), NSStringFromCGRect(previewView_.bounds));
    }
    
    CGContextRestoreGState(ctx);
}
/*
 - (void)awakeFromNib
 {
 <b style="color:black;background-color:#ffff66">CALayer</b>* layer = [<b style="color:black;background-color:#ffff66">CALayer</b> layer];
 layer.delegate = self;
 layer.bounds = [self bounds];
 layer.needsDisplayOnBoundsChange = YES; // リサイズ時に再<b style="color:black;background-color:#a0ffff">描画</b>する
 [layer setNeedsDisplay];
 [self setLayer:layer];
 [self setWantsLayer:YES];
 }
 
 - (void)drawLayer:(<b style="color:black;background-color:#ffff66">CALayer</b> *)layer inContext:(CGContextRef)context
 {
 CGContextSetRGBFillColor(context, 1.0f, 0.0f, 0.0f, 1.0f);
 rect = CGRectInset([self bounds], 40, 40);
 CGContextFillRect(context, rect);
 }*/
#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    BOOL isVideoFrame = (captureOutput == (AVCaptureOutput *)videoOutput_);
    
    if(isVideoFrame)
    {
        CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        
        /*
         image = [CIFilter filterWithName:@"CIFalseColor" keysAndValues:
         kCIInputImageKey, image,
         @"inputColor0", [CIColor colorWithRed:0.0 green:0.2 blue:0.0],
         @"inputColor1", [CIColor colorWithRed:0.0 green:0.0 blue:1.0],
         nil].outputImage;*/
        //[coreImageContext_ drawImage:image atPoint:CGPointZero fromRect:[image extent] ];
        //[self.context presentRenderbuffer:GL_RENDERBUFFER];
        
        // face detection
        NSArray *features = [faceDetector_
                             featuresInImage:image
                             options:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:imageOrientation_] forKey:CIDetectorImageOrientation]];
        
        // 座標変換
        NSMutableArray *ary = [[NSMutableArray alloc] initWithCapacity:10];
        if([features count] > 0) {
            CIFaceFeature *f = (CIFaceFeature *)[features objectAtIndex:0];
            CGRect r = f.bounds;
            CGRect rect = CGRectMake((480 - r.origin.x - r.size.width) *  255.0 / 480.0,
                                     (640 - r.origin.y)    * 255.0/ 640.0,
                                     r.size.width   * 255.0 / 480.0,
                                     r.size.height  * 255.0 / 640.0);
            [ary addObject:[NSValue valueWithCGRect:rect]];
        }
        
        // invoke delegate
        dispatch_async(dispatch_get_main_queue(), ^{
            features_ = features;
            [layer_ setNeedsDisplay];
            [self.delegate detectionUpdated:ary];
        });
    }
}
@end
