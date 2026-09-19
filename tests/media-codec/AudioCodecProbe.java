import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import java.nio.ByteBuffer;
import java.util.zip.CRC32;

/** Checks AAC selection and optionally decodes a local audio track to PCM. */
public final class AudioCodecProbe {
    public static void main(String[] args) throws Exception {
        MediaCodecList list = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
        MediaFormat xhe = MediaFormat.createAudioFormat("audio/mp4a-latm", 44100, 2);
        xhe.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectXHE);
        xhe.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectXHE);
        MediaFormat lc = MediaFormat.createAudioFormat("audio/mp4a-latm", 44100, 2);
        lc.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
        lc.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
        boolean ffmpegSeen = false;
        for (MediaCodecInfo info : list.getCodecInfos()) {
            if (!info.getName().equals("c2.ffmpeg.aac.decoder")) continue;
            ffmpegSeen = true;
            MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType("audio/mp4a-latm");
            if (caps.isFormatSupported(xhe) || !caps.isFormatSupported(lc)) {
                throw new AssertionError("Incorrect FFmpeg AAC profile declaration");
            }
        }
        if (!ffmpegSeen || !"c2.android.aac.decoder".equals(list.findDecoderForFormat(xhe))
                || !"c2.android.aac.decoder".equals(list.findDecoderForFormat(lc))) {
            throw new AssertionError("Incorrect AAC decoder selection");
        }
        System.out.println("CAPABILITIES PASS: platform AAC preferred; FFmpeg excludes xHE-AAC");
        if (args.length == 0) return;
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(args[0]);
            int track = -1;
            for (int i = 0; i < extractor.getTrackCount(); ++i) {
                if (extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith("audio/")) {
                    track = i;
                    break;
                }
            }
            if (track < 0) throw new AssertionError("No audio track");
            extractor.selectTrack(track);
            MediaFormat format = extractor.getTrackFormat(track);
            String name = args.length > 1 ? args[1] : list.findDecoderForFormat(format);
            System.out.println("SELECT " + name + " " + format);
            codec = MediaCodec.createByCodecName(name);
            codec.configure(format, null, null, 0);
            codec.start();
            int inputs = 0, outputs = 0, changes = 0;
            long lastCrc = -1, lastPts = Long.MIN_VALUE;
            boolean inputDone = false, outputDone = false;
            long deadline = System.nanoTime() + 30_000_000_000L;
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            while (!outputDone && System.nanoTime() < deadline) {
                if (!inputDone) {
                    int index = codec.dequeueInputBuffer(10000);
                    if (index >= 0) {
                        int size = extractor.readSampleData(codec.getInputBuffer(index), 0);
                        if (size < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            codec.queueInputBuffer(index, 0, size, extractor.getSampleTime(), 0);
                            ++inputs;
                            extractor.advance();
                        }
                    }
                }
                int index = codec.dequeueOutputBuffer(info, 10000);
                if (index < 0) continue;
                if (info.size > 0) {
                    ByteBuffer data = codec.getOutputBuffer(index).duplicate();
                    data.position(info.offset);
                    data.limit(info.offset + info.size);
                    CRC32 crc = new CRC32();
                    crc.update(data);
                    if (lastCrc != -1 && lastCrc != crc.getValue()) ++changes;
                    lastCrc = crc.getValue();
                    if (info.presentationTimeUs < lastPts) throw new AssertionError("PTS reversed");
                    lastPts = info.presentationTimeUs;
                    ++outputs;
                }
                outputDone = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                codec.releaseOutputBuffer(index, false);
            }
            System.out.println("RESULT inputs=" + inputs + " outputs=" + outputs
                    + " changed_buffers=" + changes + " eos=" + outputDone);
            // Priming and padding can make PCM buffer count differ from packet count.
            if (!outputDone || outputs == 0 || changes == 0) throw new AssertionError("Decode failed");
            codec.stop();
        } finally {
            if (codec != null) codec.release();
            extractor.release();
        }
    }
}
