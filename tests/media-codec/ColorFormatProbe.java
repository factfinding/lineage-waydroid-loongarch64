import android.graphics.ImageFormat;
import android.media.Image;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import java.nio.ByteBuffer;
import java.util.concurrent.FutureTask;

// Input: generated 320x240, 12-frame solid-red H.264, no B frames.
// Unlike a frame-count-only test, checks the actual negotiated pixel layout.
public final class ColorFormatProbe {
    private static final int YUV = MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar;
    private static final int RGBA = MediaCodecInfo.CodecCapabilities.COLOR_FormatRGBAFlexible;
    private static final int RGB565 = MediaCodecInfo.CodecCapabilities.COLOR_Format16bitRGB565;

    private static void require(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }

    private static int sample(Image.Plane plane, int x, int y) {
        ByteBuffer b = plane.getBuffer();
        return b.get(b.position() + y * plane.getRowStride() + x * plane.getPixelStride()) & 255;
    }

    private static void checkRed(MediaCodec codec, int index, MediaCodec.BufferInfo info,
            int requested) {
        MediaFormat format = codec.getOutputFormat(index);
        require(format.getInteger(MediaFormat.KEY_COLOR_FORMAT) == requested,
                "Requested " + requested + " but got " + format);
        if (requested == YUV || requested == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible) {
            try (Image image = codec.getOutputImage(index)) {
                require(image != null && image.getFormat() == ImageFormat.YUV_420_888, "No YUV image");
                Image.Plane[] p = image.getPlanes();
                int y = sample(p[0], 10, 10), u = sample(p[1], 5, 5), v = sample(p[2], 5, 5);
                require(y >= 70 && y <= 90 && u >= 80 && u <= 100 && v >= 230 && v <= 250,
                        "Wrong YUV red: " + y + "," + u + "," + v);
            }
        } else {
            ByteBuffer b = codec.getOutputBuffer(index).duplicate();
            b.position(info.offset);
            int a = b.get() & 255, c = b.get() & 255;
            if (requested == RGB565) {
                int pixel = a | c << 8;
                require((pixel & 0xf800) >= 0xe800 && (pixel & 0x7e0) <= 0x40 && (pixel & 31) <= 1,
                        "Wrong RGB565 red: " + Integer.toHexString(pixel));
            } else {
                // Framework's standard RGBAFlexible mapping selects HAL BGRA_8888.
                int r = b.get() & 255, alpha = b.get() & 255;
                require(a <= 10 && c <= 10 && r >= 240 && alpha >= 240,
                        "Wrong BGRA red: " + a + "," + c + "," + r + "," + alpha);
            }
        }
    }

    private static void decode(String path, int requested, boolean reject) throws Exception {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(path);
            extractor.selectTrack(0);
            MediaFormat format = extractor.getTrackFormat(0);
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, requested);
            codec = MediaCodec.createByCodecName("c2.ffmpeg.h264.decoder");
            try {
                codec.configure(format, null, null, 0);
            } catch (IllegalArgumentException | MediaCodec.CodecException e) {
                if (!reject) throw e;
                System.out.println("PASS rejected unsupported format=" + requested);
                return;
            }
            require(!reject, "Unsupported format silently accepted: " + requested);
            codec.start();
            int inputs = 0, outputs = 0;
            boolean inputEos = false, outputEos = false;
            long deadline = System.nanoTime() + 20_000_000_000L;
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            while (!outputEos && System.nanoTime() < deadline) {
                if (!inputEos) {
                    int index = codec.dequeueInputBuffer(10000);
                    if (index >= 0) {
                        int size = extractor.readSampleData(codec.getInputBuffer(index), 0);
                        inputEos = size < 0;
                        codec.queueInputBuffer(index, 0, inputEos ? 0 : size,
                                inputEos ? 0 : extractor.getSampleTime(),
                                inputEos ? MediaCodec.BUFFER_FLAG_END_OF_STREAM : 0);
                        if (!inputEos) { inputs++; extractor.advance(); }
                    }
                }
                int index = codec.dequeueOutputBuffer(info, 10000);
                if (index >= 0) {
                    try {
                        if (info.size > 0) { checkRed(codec, index, info, requested); outputs++; }
                        outputEos = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    } finally { codec.releaseOutputBuffer(index, false); }
                }
            }
            require(inputs == 12 && outputs == inputs && outputEos,
                    "Incomplete decode: inputs=" + inputs + " outputs=" + outputs + " eos=" + outputEos);
            System.out.println("PASS format=" + requested + " inputs=" + inputs + " outputs=" + outputs
                    + " red_pixels=true eos=" + outputEos);
            codec.stop();
        } finally {
            if (codec != null) codec.release();
            extractor.release();
        }
    }

    public static void main(String[] args) throws Exception {
        if (args[1].equals("mixed")) {
            FutureTask<Void> yuv = new FutureTask<>(() -> { decode(args[0], YUV, false); return null; });
            FutureTask<Void> rgb = new FutureTask<>(() -> { decode(args[0], RGBA, false); return null; });
            new Thread(yuv, "YUV-probe").start();
            new Thread(rgb, "RGBA-probe").start();
            yuv.get(); rgb.get();
        } else {
            decode(args[0], Integer.decode(args[1]), args.length > 2 && args[2].equals("reject"));
        }
    }
}
