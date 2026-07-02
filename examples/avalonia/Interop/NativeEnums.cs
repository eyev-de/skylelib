namespace SkyleAvaloniaExample.Interop;

/// <summary>Mirror of <c>eap_connection_state</c> (eap_client.h).</summary>
internal enum EapConnectionState
{
    Disconnected = 0,
    WaitingPing,
    HandshakeSent,
    WaitingSyn,
    SynAckSent,
    Connected,
    WaitingStartEapAck,
    LinkSynced,
    Error,
}

/// <summary>Mirror of <c>eap_result</c> (eap_client.h).</summary>
internal enum EapResult
{
    Ok = 0,
    NotFound = -1,
    Timeout = -2,
    InvalidState = -3,
    Communication = -4,
    Parse = -5,
    Memory = -6,
}

/// <summary>Mirror of <c>eap_eye_movement_type</c> (eap_types.h).</summary>
internal enum EapEyeMovementType : byte
{
    Fixation = 0,
    Saccade = 1,
    Unknown = 2,
}
