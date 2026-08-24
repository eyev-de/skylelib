namespace SkyleAvaloniaExample.Interop;

/// <summary>Mirror of <c>skyle_connection_state</c> (skyle_client.h).</summary>
internal enum SkyleConnectionState
{
    Disconnected = 0,
    WaitingPing,
    HandshakeSent,
    WaitingSyn,
    SynAckSent,
    Connected,
    WaitingStartAck,
    LinkSynced,
    Error,
}

/// <summary>Mirror of <c>skyle_result</c> (skyle_client.h).</summary>
internal enum SkyleResult
{
    Ok = 0,
    NotFound = -1,
    Timeout = -2,
    InvalidState = -3,
    Communication = -4,
    Parse = -5,
    Memory = -6,
}

/// <summary>Mirror of <c>skyle_eye_movement_type</c> (skyle_types.h).</summary>
internal enum SkyleEyeMovementType : byte
{
    Fixation = 0,
    Saccade = 1,
    Unknown = 2,
}
