#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dav1d/dav1d.h>
#include <jni.h>
#include <string>
extern "C" void dav1d_set_cpu_flags_mask(unsigned);
extern "C" JNIEXPORT jstring JNICALL
Java_com_example_dav1dprobe_MainActivity_run(JNIEnv *env, jclass,
                                             jboolean scalar, jint threads) {
  dav1d_set_cpu_flags_mask(scalar ? 0 : ~0u);
  std::string out = scalar ? "SCALAR\n" : "ASM\n";
  Dav1dSettings settings;
  dav1d_default_settings(&settings);
  settings.n_threads = threads;
  settings.max_frame_delay = threads;
  Dav1dContext *ctx = nullptr;
  if (dav1d_open(&ctx, &settings) < 0)
    return env->NewStringUTF("open failed");
  FILE *file = fopen("/data/local/tmp/av1-probe.ivf", "rb");
  if (!file) {
    dav1d_close(&ctx);
    return env->NewStringUTF("file failed");
  }
  unsigned char header[32];
  if (fread(header, 1, 32, file) != 32)
    abort();
  int frames = 0;
  auto drain = [&]() {
    Dav1dPicture pic{};
    int r;
    while ((r = dav1d_get_picture(ctx, &pic)) == 0) {
      uint64_t hash = 14695981039346656037ull;
      FILE *raw =
          frames == 0
              ? fopen(
                    scalar
                        ? "/data/user/0/com.example.dav1dprobe/files/scalar.yuv"
                        : "/data/user/0/com.example.dav1dprobe/files/asm.yuv",
                    "wb")
              : nullptr;
      if (pic.p.bpc != 8 || pic.p.layout != DAV1D_PIXEL_LAYOUT_I420)
        abort();
      for (int p = 0; p < 3; p++) {
        int w = p == 0 ? pic.p.w : (pic.p.w + 1) / 2;
        int h = p == 0 ? pic.p.h : (pic.p.h + 1) / 2;
        auto data = static_cast<const uint8_t *>(pic.data[p]);
        if (raw)
          for (int y = 0; y < h; y++)
            fwrite(data + y * pic.stride[p != 0], 1, w, raw);
        for (int y = 0; y < h; y++)
          for (int x = 0; x < w; x++) {
            hash ^= data[y * pic.stride[p != 0] + x];
            hash *= 1099511628211ull;
          }
      }
      if (raw)
        fclose(raw);
      char line[128];
      snprintf(line, sizeof(line), "frame=%d width=%d height=%d hash=%016llx\n",
               frames++, pic.p.w, pic.p.h, (unsigned long long)hash);
      out += line;
      dav1d_picture_unref(&pic);
    }
    return r;
  };
  unsigned char fh[12];
  while (fread(fh, 1, 12, file) == 12) {
    unsigned len = fh[0] | (unsigned(fh[1]) << 8) | (unsigned(fh[2]) << 16) |
                   (unsigned(fh[3]) << 24);
    if (len > 16 * 1024 * 1024)
      abort();
    Dav1dData data{};
    auto bytes = dav1d_data_create(&data, len);
    if (!bytes || fread(bytes, 1, len, file) != len)
      abort();
    while (data.sz) {
      int r = dav1d_send_data(ctx, &data);
      if (r < 0 && r != DAV1D_ERR(EAGAIN)) {
        out += "send failed\n";
        break;
      }
      drain();
    }
    dav1d_data_unref(&data);
  }
  drain();
  fclose(file);
  dav1d_close(&ctx);
  out += "DONE frames=" + std::to_string(frames) + "\n";
  return env->NewStringUTF(out.c_str());
}

extern "C" int dav1d_checkasm_main(int, char **);
extern "C" JNIEXPORT jstring JNICALL
Java_com_example_dav1dprobe_MainActivity_check(JNIEnv *env, jclass,
                                               jstring test) {
  const char *t = env->GetStringUTFChars(test, nullptr);
  std::string requested(t);
  auto colon = requested.find(':');
  std::string option = std::string("--test=") + requested.substr(0, colon);
  std::string function =
      std::string("--function=") +
      (colon == std::string::npos ? "*" : requested.substr(colon + 1));
  env->ReleaseStringUTFChars(test, t);
  freopen("/data/user/0/com.example.dav1dprobe/files/checkasm.txt", "w",
          stderr);
  setvbuf(stderr, nullptr, _IONBF, 0);
  char name[] = "checkasm", seed[] = "1";
  char verbose[] = "--verbose";
  char *args[] = {name, option.data(), function.data(), seed, verbose, nullptr};
  int r = dav1d_checkasm_main(colon == std::string::npos ? 4 : 5, args);
  fflush(stderr);
  return env->NewStringUTF(("checkasm result=" + std::to_string(r)).c_str());
}
