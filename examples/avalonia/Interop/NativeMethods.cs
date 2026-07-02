using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace SkyleAvaloniaExample.Interop;

/// <summary>
/// P/Invoke surface for the skylelib shared library plus a resolver that loads
/// the copy of the library placed next to the executable by the build.
/// </summary>
internal static class NativeMethods
{
    public const string Lib = "skylelib";

    private static IntPtr _handle;
    private static readonly object Gate = new();

    static NativeMethods()
    {
        NativeLibrary.SetDllImportResolver(typeof(NativeMethods).Assembly,
            (name, _, _) => name == Lib ? LibraryHandle : IntPtr.Zero);
    }

    /// <summary>Loaded module handle (also used for <see cref="NativeLibrary.GetExport"/>).</summary>
    public static IntPtr LibraryHandle
    {
        get
        {
            lock (Gate)
            {
                if (_handle != IntPtr.Zero) return _handle;
                foreach (var candidate in Candidates())
                {
                    if (NativeLibrary.TryLoad(candidate, out _handle)) return _handle;
                    var full = Path.Combine(AppContext.BaseDirectory, candidate);
                    if (File.Exists(full) && NativeLibrary.TryLoad(full, out _handle)) return _handle;
                }
                throw new DllNotFoundException(
                    "Could not load the skylelib native library. Build the C library and make " +
                    "sure the shared library is copied next to the executable (see README.md).");
            }
        }
    }

    private static IEnumerable<string> Candidates()
    {
        if (OperatingSystem.IsMacOS())
        {
            yield return "libskylelib.dylib";
            yield return "libskylelib.0.1.0.dylib";
        }
        else if (OperatingSystem.IsWindows())
        {
            yield return "skylelib.dll";
        }
        else
        {
            yield return "libskylelib.so";
            yield return "libskylelib.so.0.1.0";
        }
    }

    // ---- Client lifecycle / streaming ----

    [DllImport(Lib)] public static extern IntPtr eap_client_get_instance();
    [DllImport(Lib)] public static extern int eap_client_set_transport(IntPtr client, ref EapTransportConfig cfg);
    [DllImport(Lib)] public static extern int eap_client_set_callbacks(IntPtr client, ref EapCallbackConfig cfg);
    [DllImport(Lib)] public static extern int eap_client_connect(IntPtr client);
    [DllImport(Lib)] public static extern int eap_client_disconnect(IntPtr client);
    [DllImport(Lib)] public static extern int eap_client_get_state(IntPtr client);
    [DllImport(Lib)] public static extern int eap_client_stop_background(IntPtr client);
    [DllImport(Lib)] public static extern int eap_client_request_version(IntPtr client);

    [DllImport(Lib)] public static extern int eap_client_enable_gaze(IntPtr client, [MarshalAs(UnmanagedType.U1)] bool enable);
    [DllImport(Lib)] public static extern int eap_client_enable_positioning(IntPtr client, [MarshalAs(UnmanagedType.U1)] bool enable);
    [DllImport(Lib)] public static extern int eap_client_enable_video(IntPtr client, [MarshalAs(UnmanagedType.U1)] bool enable);

    // ---- macOS IOKit transport ----

    [DllImport(Lib)] public static extern IntPtr eap_transport_iokit_create(ref EapTransportIokitConfig cfg);
    [DllImport(Lib)] public static extern void eap_transport_iokit_destroy(IntPtr transport);
    [DllImport(Lib)] public static extern IntPtr eap_transport_iokit_get_check_callback();

    // ---- Windows WinUSB transport ----

    [DllImport(Lib)] public static extern IntPtr eap_transport_usb_create(ref EapTransportUsbConfig cfg);
    [DllImport(Lib)] public static extern void eap_transport_usb_destroy(IntPtr transport);
    [DllImport(Lib)] public static extern IntPtr eap_transport_usb_get_check_callback();
}
