package com.example.dav1dprobe;
import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;
public class MainActivity extends Activity {
    static { System.loadLibrary("dav1dprobe"); }
    static native String run(boolean scalar, int threads);
    static native String check(String test);
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved); getFilesDir();
        TextView text = new TextView(this); text.setText("Decoding..."); setContentView(text);
        new Thread(() -> {
            String test = getIntent().getStringExtra("test");
            if (test != null) { Log.i("Dav1dProbe",check(test)); return; }
            int threads = getIntent().getIntExtra("threads", 1);
            if (threads < 1 || threads > 16) throw new IllegalArgumentException("threads must be 1..16");
            Log.i("Dav1dProbe", "threads=" + threads);
            String result = run(true, threads); Log.i("Dav1dProbe",result);
            result += run(false, threads); Log.i("Dav1dProbe",result);
            final String display = result;
            runOnUiThread(() -> text.setText(display));
        }).start();
    }
}
