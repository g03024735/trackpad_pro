#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <CoreFoundation/CoreFoundation.h>

// ---- MultitouchSupport.framework (私有框架) 的结构体与函数声明 ----
// 布局来源于社区逆向（OpenMultitouchSupport / MiddleClick 等项目均使用此布局）。

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

// 触点状态
typedef enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7
} MTTouchState;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;     // 触点 id（同一根手指按住期间不变）
    int32_t state;          // MTTouchState
    int32_t fingerID;
    int32_t handID;
    MTVector normalized;    // 归一化坐标：x 0(左)~1(右)，y 0(下)~1(上)
    float total;            // 总电容（接触面积）
    float pressure;         // 压力
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;      // 毫米坐标
    int32_t unknown2[2];
    float zDensity;
} MTTouch;

typedef void *MTDeviceRef;

typedef void (*MTContactCallbackFunction)(MTDeviceRef device,
                                          MTTouch *touches,
                                          int32_t numTouches,
                                          double timestamp,
                                          int32_t frame);

CFArrayRef  MTDeviceCreateList(void);
MTDeviceRef MTDeviceCreateDefault(void);
void        MTRegisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void        MTUnregisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void        MTDeviceStart(MTDeviceRef device, int32_t mode);
void        MTDeviceStop(MTDeviceRef device);
void        MTDeviceRelease(MTDeviceRef device);
bool        MTDeviceIsBuiltIn(MTDeviceRef device);

#endif
