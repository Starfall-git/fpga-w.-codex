// Live entry point for the official EVSoC-derived gesture application.
// AR0135 RAW8 -> fixed center ROI -> 64x64 -> INT8 -> official TinyML Invoke.
#include "gesture_result.h"

struct CnnLiveStatus {
   uint32_t magic, abi_version, stage, error, clint_hz, arena_used;
   uint32_t completed, published, frame, predicted_class;
   int32_t output[3];
   uint32_t invoke_ticks, copy_ticks, period_ticks, input_checksum, input_min, input_max;
   uint32_t capture_errors, publish_busy, requested, pause_after_completed;
};
extern "C" {
   volatile CnnLiveStatus cnn_live_status;
   // TFLM may reuse its input allocation during Invoke. Preserve only when a
   // debugger requests a coherent comparison; normal inference skips this copy.
   volatile int8_t cnn_live_input[4096];
}
static const uintptr_t cnn_apb = IO_APB_SLAVE_1_INPUT;
static void live_stage(uint32_t stage) {
   cnn_live_status.stage = stage;
   asm volatile("fence rw, rw\n.word 0x500f\nfence rw, rw" ::: "memory");
}
static int live_fail(uint32_t error) {
   gesture_set_ready(cnn_apb, 0);
   cnn_live_status.error = error;
   live_stage(255);
   return 1;
}
static bool capture_wait() {
   const uint64_t begin = clint_getTime(BSP_CLINT);
   while (!(read_u32(cnn_apb + 0x44) & 5u)) {
      if (clint_getTime(BSP_CLINT) - begin > uint64_t(SYSTEM_CLINT_HZ)*2u) return false;
   }
   return (read_u32(cnn_apb + 0x44) & 7u) == 1u && read_u32(cnn_apb + 0x58) == 4096;
}
static void capture_request() {
   asm volatile("fence iorw, iorw" ::: "memory");
   write_u32(1, cnn_apb + 0x48);
}
int main() {
   cnn_live_status.magic = 0x474c5631; // GLV1
   cnn_live_status.abi_version = 1;
   cnn_live_status.clint_hz = SYSTEM_CLINT_HZ;
   live_stage(1);
   bsp_init();
   gesture_set_ready(cnn_apb, 0);
   dma_init(); // Official accelerator interrupts; legacy camera DMA remains gated.
   const u32 hart = csr_read(mhartid);
   if (hart != 0) return live_fail(1);
   arena[hart] = arena_create(500000);
   if (!arena[hart]) return live_fail(2);
   live_stage(2);
   tinyml_init();
   init_accel(hart);
   cnn_live_status.arena_used = interpreter->arena_used_bytes();
   TfLiteTensor* output = interpreter->output(0);
   if (interpreter->inputs_size()!=1 || interpreter->outputs_size()!=1 ||
       model_input->type!=kTfLiteInt8 || output->type!=kTfLiteInt8 ||
       model_input->dims->size!=4 || model_input->dims->data[0]!=1 ||
       model_input->dims->data[1]!=64 || model_input->dims->data[2]!=64 ||
       model_input->dims->data[3]!=1 || model_input->bytes!=4096 || output->bytes!=3 ||
       model_input->params.scale!=cnn_input_scale || model_input->params.zero_point!=-128 ||
       output->params.scale!=cnn_output_scale || output->params.zero_point!=cnn_output_zero_point)
      return live_fail(3);
   if (read_u32(cnn_apb+0x40)!=0x43415031 ||
       read_u32(cnn_apb+0x50)!=((104u<<16)|384u) ||
       read_u32(cnn_apb+0x54)!=((616u<<16)|896u)) return live_fail(4);
   live_stage(3);
   capture_request();
   if (!capture_wait()) return live_fail(5);
   gesture_set_ready(cnn_apb, 1);
   bool enabled_before = false;
   uint64_t previous_begin = 0;
   for (;;) {
      cnn_live_status.requested = gesture_inference_enabled(cnn_apb);
      if (!cnn_live_status.requested) {
         enabled_before = false;
         live_stage(4); // Initialized and camera verified; waiting for UART enable.
         msDelay(20);
         continue;
      }
      if (!enabled_before) {
         // Discard a snapshot held while disabled; wait for an outstanding capture.
         if (!capture_wait()) return live_fail(6);
         capture_request();
         enabled_before = true;
      }
      live_stage(5);
      if (!capture_wait()) {
         cnn_live_status.capture_errors++;
         return live_fail(7); // No stale frame inference after a camera fault.
      }
      if (!gesture_inference_enabled(cnn_apb)) continue;
      const uint64_t begin = clint_getTime(BSP_CLINT);
      cnn_live_status.period_ticks = previous_begin ? uint32_t(begin-previous_begin) : 0;
      previous_begin = begin;
      cnn_live_status.frame = read_u32(cnn_apb+0x4c);
      uint32_t checksum=2166136261u, lo=255, hi=0;
      const bool preserve_input = cnn_live_status.pause_after_completed != 0;
      for (unsigned word=0; word<1024; ++word) {
         uint32_t raw = read_u32(cnn_apb+0x1000+4*word);
         for (unsigned byte=0; byte<4; ++byte) {
            const uint32_t pixel = (raw>>(8*byte))&255u;
            // Defined signed conversion; identical to uint8 XOR 0x80 in memory.
            model_input->data.int8[4*word+byte] = int(pixel)-128;
            if (preserve_input) cnn_live_input[4*word+byte] = int(pixel)-128;
            checksum = (checksum ^ pixel)*16777619u;
            if (pixel<lo) lo=pixel;
            if (pixel>hi) hi=pixel;
         }
      }
      cnn_live_status.input_checksum=checksum;
      cnn_live_status.input_min=lo; cnn_live_status.input_max=hi;
      cnn_live_status.copy_ticks=uint32_t(clint_getTime(BSP_CLINT)-begin);
      capture_request(); // RAM ownership returned only after all input bytes copied.
      if (!gesture_inference_enabled(cnn_apb)) continue;
      live_stage(6);
      const uint64_t invoke_begin=clint_getTime(BSP_CLINT);
      if (interpreter->Invoke()!=kTfLiteOk) return live_fail(8);
      cnn_live_status.invoke_ticks=uint32_t(clint_getTime(BSP_CLINT)-invoke_begin);
      unsigned cls=0;
      for (unsigned k=0; k<3; ++k) {
         cnn_live_status.output[k]=output->data.int8[k];
         if (output->data.int8[k]>output->data.int8[cls]) cls=k;
      }
      cnn_live_status.predicted_class=cls;
      cnn_live_status.completed++;
      if (gesture_inference_enabled(cnn_apb)) {
         // This is the classification ROI, not an object detection bounding box.
         int sent=gesture_publish_result(cnn_apb,cnn_live_status.frame,384,104,896,616,1,cls);
         if (sent==1) cnn_live_status.published++;
         else cnn_live_status.publish_busy++;
      }
      live_stage(7);
      // Optional JTAG inspection of a coherent input/output pair, no breakpoints.
      while (cnn_live_status.pause_after_completed &&
             cnn_live_status.completed>=cnn_live_status.pause_after_completed) {
         live_stage(8);
         msDelay(10);
      }
   }
}
