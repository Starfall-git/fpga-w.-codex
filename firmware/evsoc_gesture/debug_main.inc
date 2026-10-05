// Replacement for the YOLO demo's main() during static accelerator validation.
// Official initialization/Invoke remain intact. This record makes their results
// visible through JTAG while the SoC UART is not wired to the board UART.
struct CnnDebugStatus {
   uint32_t magic;
   uint32_t abi_version;
   uint32_t stage;
   uint32_t error;
   uint32_t sample;
   uint32_t completed;
   uint32_t passed;
   uint32_t clint_hz;
   uint32_t arena_used;
   int32_t actual[3][3];
   int32_t expected[3][3];
   uint32_t ticks_lo[3];
   uint32_t ticks_hi[3];
};

extern "C" {
   volatile CnnDebugStatus cnn_debug_status;
   // A stable breakpoint after the record is complete, including error returns.
   __attribute__((noinline, used)) void cnn_debug_done() {
      asm volatile ("fence rw, rw" ::: "memory");
   }
}

static void cnn_debug_stage(uint32_t stage) {
   cnn_debug_status.stage = stage;
   // Same D-cache flush instruction as official EVSoC flush_data_cache().
   // Volatile alone does not publish dirty cache lines for JTAG memory reads.
   asm volatile ("fence rw, rw\n.word 0x500f\nfence rw, rw" ::: "memory");
}

static int cnn_debug_finish(uint32_t error) {
   cnn_debug_status.error = error;
   cnn_debug_stage(error == 0 ? 9 : 255);
   cnn_debug_done();
   return error == 0 ? 0 : 1;
}

int main() {
   cnn_debug_status.magic = 0x47444231; // GDB1, not the APB firmware-ready magic.
   cnn_debug_status.abi_version = 1;
   cnn_debug_status.sample = 0xffffffff;
   cnn_debug_status.clint_hz = SYSTEM_CLINT_HZ;
   cnn_debug_stage(1);
   bsp_init();
   dma_init(); // Official PLIC A initialization; absent camera DMA B is gated.
   const u32 hartId = csr_read(mhartid);
   if (hartId != 0) return cnn_debug_finish(1);
   cnn_debug_stage(2);
   arena[hartId] = arena_create(500000);
   if (arena[hartId] == nullptr) return cnn_debug_finish(2);
   cnn_debug_stage(3);
   tinyml_init();
   cnn_debug_status.arena_used = interpreter->arena_used_bytes();
   cnn_debug_stage(4);
   init_accel(hartId);
   print_accel(hartId);
   cnn_debug_stage(5);
   TfLiteTensor* output = interpreter->output(0);
   if (interpreter->inputs_size() != 1 || interpreter->outputs_size() != 1 ||
       model_input->type != kTfLiteInt8 || output->type != kTfLiteInt8 ||
       model_input->dims->size != 4 || model_input->dims->data[0] != 1 ||
       model_input->dims->data[1] != 64 || model_input->dims->data[2] != 64 ||
       model_input->dims->data[3] != 1 || output->dims->size != 2 ||
       output->dims->data[0] != 1 || output->dims->data[1] != 3 ||
       model_input->bytes != CNN_INPUT_BYTES || output->bytes != CNN_OUTPUT_CLASSES ||
       model_input->params.scale != cnn_input_scale ||
       model_input->params.zero_point != cnn_input_zero_point ||
       output->params.scale != cnn_output_scale || output->params.zero_point != cnn_output_zero_point) {
      return cnn_debug_finish(3);
   }
   const int8_t* inputs[] = {cnn_golden_0_input, cnn_golden_1_input, cnn_golden_2_input};
   const int8_t* expected[] = {cnn_golden_0_output, cnn_golden_1_output, cnn_golden_2_output};
   static_assert(CNN_GOLDEN_COUNT == 3 && CNN_OUTPUT_CLASSES == 3, "debug record contract");
   for (int sample = 0; sample < CNN_GOLDEN_COUNT; ++sample) {
      cnn_debug_status.sample = sample;
      cnn_debug_stage(6);
      for (int i = 0; i < CNN_INPUT_BYTES; ++i) model_input->data.int8[i] = inputs[sample][i];
      for (int i = 0; i < CNN_OUTPUT_CLASSES; ++i) cnn_debug_status.expected[sample][i] = expected[sample][i];
      cnn_debug_stage(7);
      const uint64_t begin = clint_getTime(BSP_CLINT);
      if (interpreter->Invoke() != kTfLiteOk) return cnn_debug_finish(4);
      const uint64_t ticks = clint_getTime(BSP_CLINT) - begin;
      cnn_debug_stage(8);
      cnn_debug_status.ticks_lo[sample] = static_cast<uint32_t>(ticks);
      cnn_debug_status.ticks_hi[sample] = static_cast<uint32_t>(ticks >> 32);
      bool match = true;
      for (int i = 0; i < CNN_OUTPUT_CLASSES; ++i) {
         cnn_debug_status.actual[sample][i] = output->data.int8[i];
         match = match && (output->data.int8[i] == expected[sample][i]);
      }
      cnn_debug_status.passed = cnn_debug_status.passed + (match ? 1 : 0);
      cnn_debug_status.completed = sample + 1;
      MicroPrintf("VECTOR %d actual=[%d,%d,%d] expected=[%d,%d,%d]\n\r", sample,
         output->data.int8[0], output->data.int8[1], output->data.int8[2],
         expected[sample][0], expected[sample][1], expected[sample][2]);
   }
   // Deliberately do not set APB firmware_ready: no live camera loop exists yet.
   return cnn_debug_finish(cnn_debug_status.passed == CNN_GOLDEN_COUNT ? 0 : 5);
}
