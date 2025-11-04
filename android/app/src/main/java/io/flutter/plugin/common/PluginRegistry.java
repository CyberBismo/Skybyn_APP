package io.flutter.plugin.common;

import android.app.Activity;
import android.content.Context;

/**
 * Compatibility shim for Flutter embedding v1 PluginRegistry.Registrar API
 * This allows old plugins (like flutter_webrtc 0.9.48) to compile with Flutter embedding v2
 */
public class PluginRegistry {
    public interface Registrar {
        Activity activity();
        Context context();
        Context activeContext();
        BinaryMessenger messenger();
        io.flutter.view.FlutterView view();
        String lookupKeyForAsset(String asset);
        String lookupKeyForAsset(String asset, String packageName);
        Registrar registrarFor(String pluginKey);
        void publish(Object value);
        void addRequestPermissionsResultListener(RequestPermissionsResultListener listener);
        void addActivityResultListener(ActivityResultListener listener);
        void addNewIntentListener(NewIntentListener listener);
        void addUserLeaveHintListener(UserLeaveHintListener listener);
        void addViewDestroyListener(ViewDestroyListener listener);
    }

    public interface RequestPermissionsResultListener {
        boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults);
    }

    public interface ActivityResultListener {
        boolean onActivityResult(int requestCode, int resultCode, android.content.Intent data);
    }

    public interface NewIntentListener {
        boolean onNewIntent(android.content.Intent intent);
    }

    public interface UserLeaveHintListener {
        void onUserLeaveHint();
    }

    public interface ViewDestroyListener {
        void onViewDestroy(io.flutter.view.FlutterView view);
    }
}

