import android.media.*;
import android.graphics.ImageFormat;
import android.hardware.HardwareBuffer;
import android.os.SystemClock;
import java.nio.ByteBuffer;
import java.util.zip.CRC32;

public final class CodecProbe {
    public static void main(String[] args) throws Exception {
        MediaCodecList list = new MediaCodecList(MediaCodecList.ALL_CODECS);
        for (MediaCodecInfo info : list.getCodecInfos()) {
            if (info.isEncoder()) continue;
            for (String type : info.getSupportedTypes()) {
                if (type.startsWith("video/")) System.out.println("CODEC " + info.getName()
                    + " " + type + " software=" + info.isSoftwareOnly()
                    + " hardware=" + info.isHardwareAccelerated());
            }
        }
        if (args.length == 0) return;
        MediaExtractor extractor = new MediaExtractor();
        extractor.setDataSource(args[0]);
        int track = -1;
        for (int i = 0; i < extractor.getTrackCount(); i++) {
            if (extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith("video/")) {
                track = i; break;
            }
        }
        if (track < 0) throw new AssertionError("No video track");
        extractor.selectTrack(track);
        MediaFormat format = extractor.getTrackFormat(track);
        String name = args.length > 1 ? args[1] : list.findDecoderForFormat(format);
        System.out.println("SELECT " + name + " " + format);
        boolean surfaceMode = args.length > 2 && args[2].equals("surface");
        ImageReader reader = surfaceMode ? ImageReader.newInstance(
            format.getInteger(MediaFormat.KEY_WIDTH), format.getInteger(MediaFormat.KEY_HEIGHT),
            ImageFormat.PRIVATE, 3, HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE) : null;
        MediaCodec codec = MediaCodec.createByCodecName(name);
        try {
            codec.configure(format, reader == null ? null : reader.getSurface(), null, 0);
            codec.start();
            boolean inputDone = false, outputDone = false;
            int inputs = 0, outputs = 0, changes = 0;
            long lastCrc = -1, lastPts = -1;
            long start = System.nanoTime(), deadline = start + 30_000_000_000L;
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            while (!outputDone && System.nanoTime() < deadline) {
                if (!inputDone) {
                    int index = codec.dequeueInputBuffer(10000);
                    if (index >= 0) {
                        ByteBuffer buffer = codec.getInputBuffer(index);
                        int size = extractor.readSampleData(buffer, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            codec.queueInputBuffer(index, 0, size, extractor.getSampleTime(), 0);
                            inputs++;
                            extractor.advance();
                        }
                    }
                }
                int index = codec.dequeueOutputBuffer(info, 10000);
                if (index >= 0) {
                    if (info.size > 0 && !surfaceMode) {
                        ByteBuffer buffer = codec.getOutputBuffer(index).duplicate();
                        buffer.position(info.offset); buffer.limit(info.offset + info.size);
                        CRC32 crc = new CRC32(); crc.update(buffer);
                        if (lastCrc != -1 && crc.getValue() != lastCrc) changes++;
                        lastCrc = crc.getValue();
                        if (info.presentationTimeUs < lastPts) throw new AssertionError("PTS reversed");
                        lastPts = info.presentationTimeUs;
                        outputs++;
                    }
                    outputDone = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    codec.releaseOutputBuffer(index, surfaceMode && info.size > 0);
                    if (surfaceMode && info.size > 0) {
                        Image frame = null;
                        long frameDeadline = System.nanoTime() + 5_000_000_000L;
                        while (frame == null && System.nanoTime() < frameDeadline) {
                            frame = reader.acquireNextImage();
                            if (frame == null) SystemClock.sleep(2);
                        }
                        if (frame == null) throw new AssertionError("Surface frame missing");
                        try {
                            long timestamp = frame.getTimestamp();
                            if (lastPts != -1 && timestamp != lastPts) changes++;
                            lastPts = timestamp;
                            outputs++;
                        } finally { frame.close(); }
                    }
                } else if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    System.out.println("OUTPUT_FORMAT " + codec.getOutputFormat());
                }
            }
            System.out.println("RESULT decoder=" + name + " inputs=" + inputs + " outputs=" + outputs
                + " surface=" + surfaceMode + " changed_frames=" + changes + " eos=" + outputDone
                + " elapsed_ms=" + (System.nanoTime() - start) / 1000000);
            if (!outputDone || outputs != inputs || changes == 0) throw new AssertionError("Decode failed");
            codec.stop();
        } finally { codec.release(); extractor.release(); if (reader != null) reader.close(); }
    }
}
