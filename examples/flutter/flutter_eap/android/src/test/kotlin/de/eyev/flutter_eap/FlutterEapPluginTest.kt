package de.eyev.flutter_eap

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import org.mockito.Mockito

internal class FlutterEapPluginTest {
  @Test
  fun onMethodCall_clearSubscriberHandle_returnsTrue() {
    val plugin = FlutterEapPlugin()

    val call = MethodCall("clearSubscriberHandle", null)
    val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(call, mockResult)

    Mockito.verify(mockResult).success(true)
  }

  @Test
  fun onMethodCall_hasUsbPermission_withoutContext_returnsFalse() {
    val plugin = FlutterEapPlugin()

    // No onAttachedToEngine: context is null, so the permission check must
    // report false without touching the Android USB service or native code.
    val call = MethodCall("hasUsbPermission", null)
    val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(call, mockResult)

    Mockito.verify(mockResult).success(false)
  }

  @Test
  fun onMethodCall_unknownMethod_returnsNotImplemented() {
    val plugin = FlutterEapPlugin()

    val call = MethodCall("getPlatformVersion", null)
    val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(call, mockResult)

    Mockito.verify(mockResult).notImplemented()
  }
}
