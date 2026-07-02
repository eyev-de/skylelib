/// EAP connection state
/// Maps to eap_connection_state enum from C library
enum ConnectionState {
  /// Not connected to device
  disconnected(0),

  /// Waiting for ping response
  waitingPing(1),

  /// Handshake sent (Android specific)
  handshakeSent(2),

  /// Waiting for SYN packet
  waitingSyn(3),

  /// SYN-ACK sent
  synAckSent(4),

  /// Basic connection established
  connected(5),

  /// Waiting for Start EAP ACK
  waitingStartEapAck(6),

  /// Link fully synchronized, ready for messages
  linkSynced(7),

  /// Connection error
  error(8);

  const ConnectionState(this.value);

  /// C enum value
  final int value;

  /// Create ConnectionState from C enum value
  factory ConnectionState.fromValue(int value) {
    return ConnectionState.values.firstWhere(
      (state) => state.value == value,
      orElse: () => ConnectionState.error,
    );
  }

  /// True if ready to send/receive EAP messages
  bool get isReady => this == ConnectionState.linkSynced;

  /// True if connected (any connection state except disconnected/error)
  bool get isConnected =>
      this != ConnectionState.disconnected && this != ConnectionState.error;
}
