const errors: Record<string, string> = {
  gpu_unavailable:
    "No supported GPU was found. Textify requires a GPU and will not use CPU inference. Install or update your GPU driver, then reopen Textify.",
  gpu_init:
    "The GPU could not start. Update your GPU driver and close other GPU-heavy apps, then reopen Textify. CPU inference is disabled.",
  gpu_model_load:
    "The model could not load on the GPU. Try a smaller model or free GPU memory. CPU inference is disabled.",
  gpu_inference:
    "The GPU could not transcribe this recording. Try a smaller model or update your GPU driver. CPU inference is disabled.",
};
export function engineError(error: unknown): string | undefined {
  return error instanceof Error ? errors[error.message] : undefined;
}
