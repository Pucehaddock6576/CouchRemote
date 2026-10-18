// MultitouchBridge.h
// Types for Apple's private MultitouchSupport.framework, which is how macOS exposes the
// Siri Remote's touch surface. Functions are looked up at runtime with dlsym (see Touchpad.swift),
// so nothing here needs linking. Struct layout follows the long-standing community headers
// (originally by Nathan Vander Wilt).

#ifndef MultitouchBridge_h
#define MultitouchBridge_h

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    int32_t state;            // 3 = make touch, 4 = touching, 5 = break touch
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector; // 0..1 position on the surface
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

typedef CFTypeRef MTDeviceRef;

typedef void (*MTFrameCallbackRefcon)(MTDeviceRef device, MTTouch *touches, size_t numTouches,
                                      double timestamp, size_t frame, void *refcon);

typedef CFArrayRef (*MTDeviceCreateListFn)(void);
typedef bool (*MTDeviceIsBuiltInFn)(MTDeviceRef device);
typedef bool (*MTDeviceIsRunningFn)(MTDeviceRef device);
typedef int32_t (*MTDeviceStartFn)(MTDeviceRef device, int mode);
typedef int32_t (*MTDeviceStopFn)(MTDeviceRef device);
typedef void (*MTRegisterCallbackFn)(MTDeviceRef device, MTFrameCallbackRefcon callback, void *refcon);
typedef void (*MTUnregisterCallbackFn)(MTDeviceRef device, MTFrameCallbackRefcon callback);
typedef int32_t (*MTDeviceGetFamilyIDFn)(MTDeviceRef device, int *familyID);
typedef int32_t (*MTDeviceGetSensorSurfaceDimensionsFn)(MTDeviceRef device, int *width, int *height);

#endif
