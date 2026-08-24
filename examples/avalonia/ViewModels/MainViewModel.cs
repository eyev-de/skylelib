using System;
using System.Threading;
using Avalonia.Media;
using Avalonia.Threading;
using SkyleAvaloniaExample.Interop;

namespace SkyleAvaloniaExample.ViewModels;

internal sealed class MainViewModel : ViewModelBase, IDisposable
{
    private readonly SkyleClient _client = new();
    private readonly DispatcherTimer _timer;

    // Latest values written from the library's I/O thread (reference swaps are atomic).
    private volatile PositioningSnapshot? _latestPos;
    private volatile GazeSnapshot? _latestGaze;
    private volatile VideoFrame? _latestVideo;
    private volatile string _latestVersion = string.Empty;
    private int _latestState = (int)SkyleConnectionState.Disconnected;

    // What the UI has already consumed.
    private PositioningSnapshot? _posShown;
    private GazeSnapshot? _gazeShown;
    private VideoFrame? _videoShown;
    private SkyleConnectionState _appliedState = (SkyleConnectionState)(-1);

    public MainViewModel()
    {
        _client.PositioningReceived += p => _latestPos = p;
        _client.GazeReceived += g => _latestGaze = g;
        _client.VideoReceived += v => _latestVideo = v;
        _client.VersionReceived += v => _latestVersion = v;
        _client.StateChanged += s => Interlocked.Exchange(ref _latestState, (int)s);

        // Single UI-thread pump decouples the ~60 Hz device streams from rendering.
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        _timer.Tick += OnTick;

        try
        {
            _client.Start();
            _timer.Start();
        }
        catch (Exception ex)
        {
            ConnectionLabel = "Load error";
            ConnectionBrush = Brushes.OrangeRed;
            DeviceInfo = ex.Message;
        }
    }

    // ---- bound properties ----

    private PositioningSnapshot? _positioning;
    public PositioningSnapshot? Positioning
    {
        get => _positioning;
        private set => SetField(ref _positioning, value);
    }

    private VideoFrame? _frame;
    public VideoFrame? Frame
    {
        get => _frame;
        private set => SetField(ref _frame, value);
    }

    private string _gazeText = "Gaze: —";
    public string GazeText
    {
        get => _gazeText;
        private set => SetField(ref _gazeText, value);
    }

    private string _connectionLabel = "Disconnected";
    public string ConnectionLabel
    {
        get => _connectionLabel;
        private set => SetField(ref _connectionLabel, value);
    }

    private IBrush _connectionBrush = Brushes.Gray;
    public IBrush ConnectionBrush
    {
        get => _connectionBrush;
        private set => SetField(ref _connectionBrush, value);
    }

    private string _deviceInfo = "No device";
    public string DeviceInfo
    {
        get => _deviceInfo;
        private set => SetField(ref _deviceInfo, value);
    }

    private bool _isPositioningSelected = true;
    public bool IsPositioningSelected
    {
        get => _isPositioningSelected;
        set
        {
            if (SetField(ref _isPositioningSelected, value))
            {
                OnPropertyChanged(nameof(ShowPositioning));
                ApplyStreams();
            }
        }
    }

    private bool _isVideoSelected;
    public bool IsVideoSelected
    {
        get => _isVideoSelected;
        set
        {
            if (SetField(ref _isVideoSelected, value))
            {
                OnPropertyChanged(nameof(ShowVideo));
                ApplyStreams();
            }
        }
    }

    public bool ShowPositioning => IsPositioningSelected;
    public bool ShowVideo => IsVideoSelected;

    // ---- Skyle Link host controls (toggle state is app-local; the commands are
    // fire-and-forget and only reach a hub-hosting Skyle app while this app is a
    // link client) ----

    private bool _hostMenuBarVisible = true;
    public bool HostMenuBarVisible
    {
        get => _hostMenuBarVisible;
        set
        {
            if (SetField(ref _hostMenuBarVisible, value))
                NoteHostControl("Menu bar", _client.SetHostMenuBarVisible(value));
        }
    }

    private bool _hostPointerVisible = true;
    public bool HostPointerVisible
    {
        get => _hostPointerVisible;
        set
        {
            if (SetField(ref _hostPointerVisible, value))
                NoteHostControl("Pointer", _client.SetHostPointerVisible(value));
        }
    }

    public void StartHostCalibration()
        => NoteHostControl("Calibrate", _client.StartHostCalibration());

    private string _hostControlNote = string.Empty;

    private void NoteHostControl(string what, int result)
    {
        _hostControlNote = result == (int)SkyleResult.Ok
            ? $"{what}: sent"
            : $"{what}: {(SkyleResult)result} (not a link client)";
        if (_appliedState != (SkyleConnectionState)(-1))
            UpdateConnectionUi(_appliedState);
    }

    // ---- UI pump ----

    private void OnTick(object? sender, EventArgs e)
    {
        var state = (SkyleConnectionState)Volatile.Read(ref _latestState);
        if (state != _appliedState)
        {
            _appliedState = state;
            UpdateConnectionUi(state);
            if (state == SkyleConnectionState.LinkSynced) ApplyStreams();
        }

        var g = _latestGaze;
        if (!ReferenceEquals(g, _gazeShown))
        {
            _gazeShown = g;
            GazeText = FormatGaze(g);
        }

        var p = _latestPos;
        if (!ReferenceEquals(p, _posShown))
        {
            _posShown = p;
            Positioning = p;
        }

        var v = _latestVideo;
        if (!ReferenceEquals(v, _videoShown))
        {
            _videoShown = v;
            Frame = v;
        }

        var version = _latestVersion;
        if (state == SkyleConnectionState.LinkSynced && version.Length > 0 && DeviceInfo != version)
            DeviceInfo = version;
    }

    private void ApplyStreams()
    {
        if (_appliedState != SkyleConnectionState.LinkSynced) return;
        _client.EnableGaze(true);                       // gaze readout is always live
        _client.EnablePositioning(IsPositioningSelected);
        _client.EnableVideo(IsVideoSelected);           // off when not viewing saves bandwidth
    }

    private void UpdateConnectionUi(SkyleConnectionState state)
    {
        string label;
        switch (state)
        {
            case SkyleConnectionState.LinkSynced:
                label = "Streaming";
                ConnectionBrush = new SolidColorBrush(Color.FromRgb(0x2E, 0xCC, 0x71)); // green
                break;
            case SkyleConnectionState.Disconnected:
                label = "Disconnected";
                ConnectionBrush = new SolidColorBrush(Color.FromRgb(0x88, 0x88, 0x88)); // gray
                DeviceInfo = "No device";
                break;
            case SkyleConnectionState.Error:
                label = "Error";
                ConnectionBrush = new SolidColorBrush(Color.FromRgb(0xE7, 0x4C, 0x3C)); // red
                break;
            default:
                label = "Connecting…";
                ConnectionBrush = new SolidColorBrush(Color.FromRgb(0xF1, 0xC4, 0x0F)); // amber
                break;
        }
        ConnectionLabel = _hostControlNote.Length > 0 ? $"{label} - {_hostControlNote}" : label;
    }

    private static string FormatGaze(GazeSnapshot? g)
        => g is { Valid: true }
            ? $"Gaze: ({g.X:0}, {g.Y:0}) px · {g.Movement}"
            : "Gaze: —";

    public void Dispose()
    {
        _timer.Stop();
        _client.Dispose();
    }
}
