#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <stdio.h>
#include <string.h>

// Invoked by Unity on its GLES render thread. Does not change GL bindings.
// glGetError consumes error flags; this is only installed in the test app.
static char output_path[2048];
static unsigned samples[256];
__attribute__((visibility("default"))) void WaterSetPath(const char* path) {
    snprintf(output_path, sizeof(output_path), "%s", path);
}
static void RenderEvent(int event) {
    // Bound diagnostic output if the user leaves a scene open after the run.
    if (event < 0 || event >= 256 || samples[event]++ >= 256) return;
    FILE* f = fopen(output_path, "a");
    if (!f) return;
    fprintf(f, "EVENT %d context=%p pre_error=0x%x\n", event,
            (void*)eglGetCurrentContext(), glGetError());
    if (eglGetCurrentContext() == EGL_NO_CONTEXT) { fclose(f); return; }
    GLint draw = 0, read = 0;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read);
    fprintf(f, "draw_fbo=%d status=0x%x read_fbo=%d status=0x%x\n", draw,
            glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER), read,
            glCheckFramebufferStatus(GL_READ_FRAMEBUFFER));
    if (event == 0) {
        fprintf(f, "GL_VERSION %s\nGL_RENDERER %s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));
        GLint count = 0; glGetIntegerv(GL_NUM_EXTENSIONS, &count);
        for (GLint i = 0; i < count; ++i)
            fprintf(f, "EXT %s\n", glGetStringi(GL_EXTENSIONS, i));
        const char* names[] = {"glBlendFuncSeparate", "glBlitFramebuffer",
            "glCheckFramebufferStatus", "glFramebufferTexture2D", "glDrawBuffers",
            "glCopyTexSubImage2D", "glTexStorage2D", "glRenderbufferStorageMultisample",
            "glFramebufferTexture2DMultisampleEXT", "glDrawElementsInstanced",
            "glVertexAttribDivisor", "glGetShaderInfoLog", "glGetProgramInfoLog",
            "glDiscardFramebufferEXT", "glInvalidateFramebuffer"};
        for (unsigned i = 0; i < sizeof(names)/sizeof(names[0]); ++i)
            fprintf(f, "PROC %s %s\n", names[i], eglGetProcAddress(names[i]) ? "present" : "NULL");
    }
    fprintf(f, "post_error=0x%x\n", glGetError());
    fclose(f);
}
__attribute__((visibility("default"))) void* WaterGetRenderEvent(void) {
    return (void*)&RenderEvent;
}
