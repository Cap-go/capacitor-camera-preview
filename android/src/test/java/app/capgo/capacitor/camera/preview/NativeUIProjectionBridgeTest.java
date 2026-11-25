package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertFalse;

import org.junit.Test;

public class NativeUIProjectionBridgeTest {
    @Test
    public void inactiveByDefault() {
        NativeUIProjectionBridge bridge = new NativeUIProjectionBridge();
        assertFalse(bridge.isActive());
    }

    @Test
    public void receiveWithoutActivateDoesNothing() {
        NativeUIProjectionBridge bridge = new NativeUIProjectionBridge();
        bridge.receive("previewAppearanceChanged", null);
        assertFalse(bridge.isActive());
    }
}