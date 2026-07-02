using System;
using System.Runtime.InteropServices;

namespace SkyleAvaloniaExample.Interop;

// ============================================================================
// Blittable mirrors of the C structs from include/skylelib/eap/...
//
// IMPORTANT FFI notes:
//  * All callback payloads are delivered in HOST byte order (big-endian is a
//    wire-only concern, decoded inside the library), so these marshal directly.
//  * Every C `bool` is 1 byte -> [MarshalAs(U1)] bool (never the default 4-byte BOOL).
//  * LayoutKind.Sequential applies the same natural alignment as C
//    (e.g. the int64 timestamp lands at offset 8; eap_complex_gaze pads to 20).
//  The struct sizes in the comments are asserted at runtime in SkyleClient.
// ============================================================================

[StructLayout(LayoutKind.Sequential)]
internal struct EapPointF // 8 bytes
{
    public float X;
    public float Y;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapSizeF // 8 bytes
{
    public float Width;
    public float Height;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapRectF // 16 bytes
{
    public float Top;
    public float Left;
    public float Bottom;
    public float Right;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapRectU // 8 bytes
{
    public ushort Top;
    public ushort Left;
    public ushort Bottom;
    public ushort Right;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapRotatedRect // 20 bytes
{
    public EapPointF Center;
    public EapSizeF Size;
    public float Angle; // degrees, OpenCV convention
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapMessageHeader // 24 bytes
{
    public ushort MessageType;
    public ushort PayloadLength;
    public long TimestampMs;
    [MarshalAs(UnmanagedType.U1)] public bool HasTimestamp;
}

// ---- Gaze ----

[StructLayout(LayoutKind.Sequential)]
internal struct EapComplexGaze // 20 bytes (17 on the wire, padded in memory)
{
    public EapPointF Raw;
    public EapPointF Smoothed;
    public byte Type; // EapEyeMovementType
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapGazeResponse
{
    public EapMessageHeader Header;
    public EapComplexGaze Left;
    public EapComplexGaze Right;
    public EapComplexGaze Both;
}

// ---- Positioning ----

[StructLayout(LayoutKind.Sequential)]
internal struct EapComplexFeature // 44 bytes
{
    public EapPointF Center;
    public EapRectF BoundingRect;
    public EapRotatedRect Ellipse;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapComplexIris // 44 bytes
{
    public EapPointF Center;
    public EapPointF Top;
    public EapPointF Left;
    public EapPointF Right;
    public EapPointF Bottom;
    public float DistanceMm;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapComplexEye // 184 bytes
{
    public EapRectU BoundingRect;   // image-space (uint16)
    public EapComplexFeature Pupil;
    public EapComplexFeature LeftGlint;
    public EapComplexFeature RightGlint;
    public EapComplexIris Iris;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapComplexEyes // 368 bytes
{
    public EapComplexEye Left;
    public EapComplexEye Right;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapComplexFace // 384 bytes
{
    public EapRectF BoundingRect;   // screen-space
    public EapComplexEyes Eyes;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapPositioningResponse
{
    public EapMessageHeader Header;
    public EapComplexFace Face;
}

// ---- Video ----

[StructLayout(LayoutKind.Sequential)]
internal struct EapVideoResponse
{
    public ushort Width;
    public ushort Height;
    public byte Channels;
    public IntPtr PixelData;        // valid only during the callback
    public uint PixelDataLength;
}

// ---- Version ----

[StructLayout(LayoutKind.Sequential)]
internal struct EapVersionResponse
{
    public EapMessageHeader Header;
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
internal struct EapTransportIokitConfig
{
    public ushort VendorId;
    public ushort ProductId;
    public uint TimeoutMs;
    [MarshalAs(UnmanagedType.U1)] public bool Verbose;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapTransportUsbConfig
{
    public ushort VendorId;
    public ushort ProductId;
    public uint TimeoutMs;
    [MarshalAs(UnmanagedType.U1)] public bool Verbose;
}

[StructLayout(LayoutKind.Sequential)]
internal struct EapTransportConfig
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
internal struct EapCallbackConfig
{
    public IntPtr OnGaze;
    public IntPtr OnPositioning;
    public IntPtr OnVersion;
    public IntPtr OnControl;
    public IntPtr OnCalibrationPoint;
    public IntPtr OnCalibrationProgress;
    public IntPtr OnCalibrationPaused;
    public IntPtr OnCalibrationFinished;
    public IntPtr OnVideo;
    public IntPtr OnFileStatus;
    public IntPtr OnLogging;
    public IntPtr OnStateChange;
    public IntPtr OnError;
    public IntPtr UserData;
}
