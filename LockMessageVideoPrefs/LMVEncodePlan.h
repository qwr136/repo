#import <math.h>

typedef struct {
    long width, height, bitrate;
    double fps;
} LMVEncodePlan;
// Pure arithmetic: budget first, not three expensive preset exports.
static LMVEncodePlan LMVMakeEncodePlan(double width, double height, double duration,
                                      double nominalFPS, unsigned long long inputBytes,
                                      long attempt, double feedbackScale) {
    double budget=fmin(5.0*1024.0*1024.0,(double)inputBytes)*0.82;
    double rate=fmin(1200000.0,budget*8.0/duration)*pow(0.60,(double)attempt)*feedbackScale;
    // Do not impose a floor that makes long videos exceed the size budget.
    long bitrate=(long)fmax(1000.0,rate);
    double limit=bitrate>=700000 ? 960 : (bitrate>=350000 ? 720 : (bitrate>=160000 ? 540 : 360));
    limit*=pow(0.80,(double)attempt);
    double scale=fmin(1.0,limit/fmax(width,height));
    double fps=isfinite(nominalFPS) && nominalFPS>0 ? fmin(30.0,nominalFPS) : 30.0;
    if (bitrate<350000) fps=fmin(fps,24.0);
    if (bitrate<160000) fps=fmin(fps,15.0);
    LMVEncodePlan plan={(long)fmax(2.0,floor(width*scale/2.0)*2.0),
                        (long)fmax(2.0,floor(height*scale/2.0)*2.0),bitrate,fps};
    return plan;
}
