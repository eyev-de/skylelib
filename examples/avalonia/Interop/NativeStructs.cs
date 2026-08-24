using System;
using System.Runtime.InteropServices;

namespace SkyleAvaloniaExample.Interop;

// ============================================================================
// Blittable mirrors of the C structs from include/skylelib/messages/...
//
// IMPORTANT FFI notes:
//  * All callback payloads are delivered in HOST byte order (big-endian is a
//    wire-only concern, decoded inside the library), so these marshal directly.
//  * Every C `bool` is 1 byte -> [MarshalAs(U1)] bool (never the default 4-byte BOOL).
//  * LayoutKind.Sequential applies the same natural alignment as C
//    (e.g. the int64 timestamp lands at offset 8; skyle_complex_gaze pads to 20).
//  The struct sizes in the comments are asserted at runtime in SkyleClient.
// ============================================================================

[StructLayout(LayoutKind.Sequential)]
internal struct SkylePointF // 8 bytes
{
    public float X;
    public float Y;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleSizeF // 8 bytes
{
    public float Width;
    public float Height;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleRectF // 16 bytes
{
    public float Top;
    public float Left;
    public float Bottom;
    public float Right;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleRectU // 8 bytes
{
    public ushort Top;
    public ushort Left;
    public ushort Bottom;
    public ushort Right;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleRotatedRect // 20 bytes
{
    public SkylePointF Center;
    public SkyleSizeF Size;
    public float Angle; // degrees, OpenCV convention
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleMessageHeader // 24 bytes
{
    public ushort MessageType;
    public ushort PayloadLength;
    public long TimestampMs;
    [MarshalAs(UnmanagedType.U1)] public bool HasTimestamp;
}

// ---- Gaze ----

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleComplexGaze // 20 bytes (17 on the wire, padded in memory)
{
    public SkylePointF Raw;
    public SkylePointF Smoothed;
    public byte Type; // SkyleEyeMovementType
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleGazeResponse
{
    public SkyleMessageHeader Header;
    public SkyleComplexGaze Left;
    public SkyleComplexGaze Right;
    public SkyleComplexGaze Both;
}

// ---- Positioning ----

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleComplexFeature // 44 bytes
{
    public SkylePointF Center;
    public SkyleRectF BoundingRect;
    public SkyleRotatedRect Ellipse;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleComplexIris // 44 bytes
{
    public SkylePointF Center;
    public SkylePointF Top;
    public SkylePointF Left;
    public SkylePointF Right;
    public SkylePointF Bottom;
    public float DistanceMm;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleComplexEye // 184 bytes
{
    public SkyleRectU BoundingRect;   // image-space (uint16)
    public SkyleComplexFeature Pupil;
    public SkyleComplexFeature LeftGlint;
    public SkyleComplexFeature RightGlint;
    public SkyleComplexIris Iris;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleComplexEyes // 368 bytes
{
    public SkyleComplexEye Left;
    public SkyleComplexEye Right;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleComplexFace // 384 bytes
{
    public SkyleRectF BoundingRect;   // screen-space
    public SkyleComplexEyes Eyes;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkylePositioningResponse
{
    public SkyleMessageHeader Header;
    public SkyleComplexFace Face;
}

// ---- Video ----

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleVideoResponse
{
    public ushort Width;
    public ushort Height;
    public byte Channels;
    public IntPtr PixelData;        // valid only during the callback
    public uint PixelDataLength;
}

// ---- Version ----

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleVersionResponse
{
    public SkyleMessageHeader Header;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] Firmware;
    public ulong Serial;
    [MarshalAs(UnmanagedType.U1)] public bool IsDemoDevice;
    public byte DeviceType;
    public byte DevicePlatform;
    public byte DeviceGeneration;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] ProtocolVersion;
}

// ---- Transport / callback configuration (passed to the library) ----

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleTransportIokitConfig
{
    public ushort VendorId;
    public ushort ProductId;
    public uint TimeoutMs;
    [MarshalAs(UnmanagedType.U1)] public bool Verbose;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleTransportUsbConfig
{
    public ushort VendorId;
    public ushort ProductId;
    public uint TimeoutMs;
    [MarshalAs(UnmanagedType.U1)] public bool Verbose;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleTransportConfig
{
    public IntPtr TransportWrite;       // native fn pointer
    public IntPtr TransportRead;        // native fn pointer
    public IntPtr TransportUserData;    // the transport handle
    public IntPtr UsbDeviceCheck;       // native fn pointer
    public uint ConnectTimeoutMs;
    public uint ReconnectIntervalMs;
    [MarshalAs(UnmanagedType.U1)] public bool Verbose;
    [MarshalAs(UnmanagedType.U1)] public bool Trace;
}

[StructLayout(LayoutKind.Sequential)]
internal struct SkyleCallbackConfig
{
    public IntPtr OnGaze;
    public IntPtr OnPositioning;
    public IntPtr OnVersion;
    public IntPtr OnControl;
    public IntPtr OnCalibrationPoint;
    public IntPtr OnCalibrationProgress;
    public IntPtr OnCalibrationPaused;
    public IntPtr OnCalibrationFinished;
    public IntPtr OnCalibrationAborted;
    public IntPtr OnVideo;
    public IntPtr OnFileStatus;
    public IntPtr OnLogging;
    public IntPtr OnStateChange;
    public IntPtr OnError;
    public IntPtr UserData;
}
