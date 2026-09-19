import android.os.Build;

import java.lang.reflect.Method;

/** Run in a fresh app_process with the compatibility property set externally. */
public final class InstagramCompatProbe {
    public static void main(String[] args) throws Exception {
        boolean enabled = Boolean.parseBoolean(args[0]);
        String original = Build.MODEL;
        Method getProperty = Class.forName("android.os.SystemProperties")
                .getMethod("get", String.class);
        String property = (String) getProperty.invoke(null, "ro.product.model");
        if (!original.equals(property)) {
            throw new AssertionError("Model override leaked into a fresh process");
        }
        Method apply = Class.forName("com.android.internal.util.WaydroidAppCompat")
                .getMethod("apply", String.class);
        for (String other : new String[] {null, "android", "com.example.app",
                "com.instagram.android.other"}) {
            apply.invoke(null, other);
            if (!original.equals(Build.MODEL)) {
                throw new AssertionError("Override affected other package: " + other);
            }
        }
        apply.invoke(null, "com.instagram.android");
        String expected = enabled ? "Waydroid Emulator" : original;
        if (!expected.equals(Build.MODEL)) {
            throw new AssertionError("Unexpected model: " + Build.MODEL);
        }
        if (!property.equals(getProperty.invoke(null, "ro.product.model"))) {
            throw new AssertionError("Global model property changed");
        }
        System.out.println("PASS enabled=" + enabled + " original=" + original
                + " appModel=" + Build.MODEL + " globalModel=" + property);
    }
}
