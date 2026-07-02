using System;
using System.Runtime.InteropServices;
using System.Text;

namespace SkyleAvaloniaExample.Interop;

/// <summary>Decoded gaze sample handed to the UI.</summary>
internal sealed class GazeSnapshot
{
    public float X { get; }
    public float Y { get; }
    public EapEyeMovementType Movement { get; }
    public bool Valid { get; }

    public GazeSnapshot(float x, float y, EapEyeMovementType movement, bool valid)
    {
        X = x; Y = y; Movement = movement; Valid = valid;
    }
}

/// <summary>One positioning frame (full face structure) for the diagnostic view.</summary>
internal sealed class PositioningSnapshot
{
    public EapComplexFace Face { get; }
    public PositioningSnapshot(EapComplexFace face) => Face = face;
}

/// <summary>One decoded video frame; pixels copied out of the transient native buffer.</summary>
internal sealed class VideoFrame
{
    public int Width { get; }
    public int Height { get; }
    public int Channels { get; }
    public byte[] Pixels { get; }

    public VideoFrame(int width, int height, int channels, byte[] pixels)
    {
        Width = width; Height = height; Channels = channels; Pixels = pixels;
    }
}

/// <summary>
/// Managed wrapper over the skylelib C client: owns the platform transport,
/// marshals callbacks off the library's background I/O thread, and raises plain
/// C# events. All events fire on a NON-UI thread — subscribers must marshal.
/// </summary>
internal sealed class SkyleClient : IDisposable
{
    private const ushort SkyleVendorId = 0x3729;
    private const ushort SkyleProductId = 0x7333;

    // Native callback delegate types (cdecl). Instances are stored in fields so
    // the GC cannot collect them while native code holds their function pointers.
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void GazeCb(IntPtr client, IntPtr gaze, IntPtr user);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PositioningCb(IntPtr client, IntPtr positioning, IntPtr user);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void VideoCb(IntPtr client, IntPtr video, IntPtr user);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void StateCb(IntPtr client, int oldState, int newState, IntPtr user);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void VersionCb(IntPtr client, IntPtr version, IntPtr user);

    private IntPtr _client;
    private IntPtr _transport;
    private bool _disposed;

    private GazeCb? _gazeCb;
    private PositioningCb? _posCb;
    private VideoCb? _videoCb;
    private StateCb? _stateCb;
    private VersionCb? _versionCb;

    public event Action<GazeSnapshot>? GazeReceived;
    public event Action<PositioningSnapshot>? PositioningReceived;
    public event Action<VideoFrame>? VideoReceived;
    public event Action<EapConnectionState>? StateChanged;
    public event Action<string>? VersionReceived;

    public void Start()
    {
        VerifyStructLayouts();

        _client = NativeMethods.eap_client_get_instance();
        if (_client == IntPtr.Zero)
            throw new InvalidOperationException("eap_client_get_instance() returned NULL.");

        SetupTransport();   // phase 1: transport (starts background I/O thread)
        SetupCallbacks();   // phase 2: message callbacks
        NativeMethods.eap_client_connect(_client);
    }

    private void SetupTransport()
    {
        IntPtr writePtr, readPtr, checkPtr;

        if (OperatingSystem.IsMacOS())
        {
            var cfg = new EapTransportIokitConfig
            {
                VendorId = SkyleVendorId,
                ProductId = SkyleProductId,
                TimeoutMs = 1000,
                Verbose = false,
            };
            _transport = NativeMethods.eap_transport_iokit_create(ref cfg);
            writePtr = NativeLibrary.GetExport(NativeMethods.LibraryHandle, "eap_transport_iokit_write");
            readPtr = NativeLibrary.GetExport(NativeMethods.LibraryHandle, "eap_transport_iokit_read");
            checkPtr = NativeMethods.eap_transport_iokit_get_check_callback();
        }
        else if (OperatingSystem.IsWindows())
        {
            var cfg = new EapTransportUsbConfig
            {
                VendorId = SkyleVendorId,
                ProductId = SkyleProductId,
                TimeoutMs = 1000,
                Verbose = false,
            };
            _transport = NativeMethods.eap_transport_usb_create(ref cfg);
            writePtr = NativeLibrary.GetExport(NativeMethods.LibraryHandle, "eap_transport_usb_write");
            readPtr = NativeLibrary.GetExport(NativeMethods.LibraryHandle, "eap_transport_usb_read");
            checkPtr = NativeMethods.eap_transport_usb_get_check_callback();
        }
        else
        {
            throw new PlatformNotSupportedException(
                "This example provides a built-in USB transport only for macOS and Windows.");
        }

        var transport = new EapTransportConfig
        {
            TransportWrite = writePtr,
            TransportRead = readPtr,
            TransportUserData = _transport,
            UsbDeviceCheck = checkPtr,
            ConnectTimeoutMs = 10000,
            ReconnectIntervalMs = 2000,
            Verbose = false,
            Trace = false,
        };
        NativeMethods.eap_client_set_transport(_client, ref transport);
    }

    private void SetupCallbacks()
    {
        _gazeCb = OnGaze;
        _posCb = OnPositioning;
        _videoCb = OnVideo;
        _stateCb = OnState;
        _versionCb = OnVersion;

        var callbacks = new EapCallbackConfig
        {
            OnGaze = Marshal.GetFunctionPointerForDelegate(_gazeCb),
            OnPositioning = Marshal.GetFunctionPointerForDelegate(_posCb),
            OnVideo = Marshal.GetFunctionPointerForDelegate(_videoCb),
            OnStateChange = Marshal.GetFunctionPointerForDelegate(_stateCb),
            OnVersion = Marshal.GetFunctionPointerForDelegate(_versionCb),
            UserData = IntPtr.Zero,
        };
        NativeMethods.eap_client_set_callbacks(_client, ref callbacks);
    }

    // ---- streaming control (safe to call from any thread) ----

    public void EnableGaze(bool enable) => SafeCall(() => NativeMethods.eap_client_enable_gaze(_client, enable));
    public void EnablePositioning(bool enable) => SafeCall(() => NativeMethods.eap_client_enable_positioning(_client, enable));
    public void EnableVideo(bool enable) => SafeCall(() => NativeMethods.eap_client_enable_video(_client, enable));

    private void SafeCall(Func<int> action)
    {
        if (_client == IntPtr.Zero || _disposed) return;
        try { action(); } catch { /* best-effort streaming toggles */ }
    }

    // ---- native callbacks (run on the library's background I/O thread) ----

    private void OnGaze(IntPtr client, IntPtr gaze, IntPtr user)
    {
        var r = Marshal.PtrToStructure<EapGazeResponse>(gaze);
        var both = r.Both;
        bool valid = both.Smoothed.X != 0f || both.Smoothed.Y != 0f;
        GazeReceived?.Invoke(new GazeSnapshot(both.Smoothed.X, both.Smoothed.Y, (EapEyeMovementType)both.Type, valid));
    }

    private void OnPositioning(IntPtr client, IntPtr positioning, IntPtr user)
    {
        var r = Marshal.PtrToStructure<EapPositioningResponse>(positioning);
        PositioningReceived?.Invoke(new PositioningSnapshot(r.Face));
    }

    private void OnVideo(IntPtr client, IntPtr video, IntPtr user)
    {
        var r = Marshal.PtrToStructure<EapVideoResponse>(video);
        int len = (int)r.PixelDataLength;
        var buffer = new byte[len];
        if (r.PixelData != IntPtr.Zero && len > 0)
            Marshal.Copy(r.PixelData, buffer, 0, len); // copy now — pointer is transient
        VideoReceived?.Invoke(new VideoFrame(r.Width, r.Height, r.Channels, buffer));
    }

    private void OnState(IntPtr client, int oldState, int newState, IntPtr user)
        => StateChanged?.Invoke((EapConnectionState)newState);

    private void OnVersion(IntPtr client, IntPtr version, IntPtr user)
    {
        var r = Marshal.PtrToStructure<EapVersionResponse>(version);
        string fw = CString(r.Firmware);
        VersionReceived?.Invoke(string.IsNullOrEmpty(fw)
            ? $"Skyle · SN {r.Serial}"
            : $"Skyle · FW {fw} · SN {r.Serial}");
    }

    private static string CString(byte[]? raw)
    {
        if (raw == null) return string.Empty;
        int n = Array.IndexOf(raw, (byte)0);
        if (n < 0) n = raw.Length;
        return Encoding.UTF8.GetString(raw, 0, n);
    }

    /// <summary>Cheap guard against alignment drift between C and the C# mirrors.</summary>
    private static void VerifyStructLayouts()
    {
        Check<EapPointF>(8);
        Check<EapRectF>(16);
        Check<EapRectU>(8);
        Check<EapRotatedRect>(20);
        Check<EapComplexFeature>(44);
        Check<EapComplexIris>(44);
        Check<EapComplexEye>(184);
        Check<EapComplexEyes>(368);
        Check<EapComplexFace>(384);

        static void Check<T>(int expected)
        {
            int actual = Marshal.SizeOf<T>();
            if (actual != expected)
                throw new InvalidOperationException(
                    $"FFI layout mismatch: {typeof(T).Name} is {actual} bytes, expected {expected}.");
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        if (_client != IntPtr.Zero)
        {
            try { NativeMethods.eap_client_disconnect(_client); } catch { /* ignore */ }
            try { NativeMethods.eap_client_stop_background(_client); } catch { /* ignore */ }
        }

        if (_transport != IntPtr.Zero)
        {
            try
            {
                if (OperatingSystem.IsMacOS()) NativeMethods.eap_transport_iokit_destroy(_transport);
                else if (OperatingSystem.IsWindows()) NativeMethods.eap_transport_usb_destroy(_transport);
            }
            catch { /* ignore */ }
            _transport = IntPtr.Zero;
        }

        // Delegates intentionally kept referenced until after the I/O thread has stopped.
        _gazeCb = null;
        _posCb = null;
        _videoCb = null;
        _stateCb = null;
        _versionCb = null;
    }
}
