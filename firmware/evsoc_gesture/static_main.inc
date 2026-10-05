// Replacement for the YOLO demo's main() during static accelerator validation.
// tinyml_init(), init_accel(), print_accel(), CLINT timing and Invoke() remain
// the official EVSoC flow. Camera/display initialization is deferred to integration.
int main() {
   bsp_init();
   const u32 hartId = csr_read(mhartid);
   if (hartId != 0) return 1;
   arena[hartId] = arena_create(500000); // Official application scratch allocator.
   if (arena[hartId] == nullptr) { MicroPrintf("FAIL scratch arena\n\r"); return 1; }
   tinyml_init();
   init_accel(hartId);
   print_accel(hartId);
   MicroPrintf("EVSOC_GESTURE_STATIC: generated model, official accelerator runtime\n\r");
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
      MicroPrintf("FAIL tensor contract\n\r"); return 1;
   }
   const int8_t* inputs[] = {cnn_golden_0_input, cnn_golden_1_input, cnn_golden_2_input};
   const int8_t* expected[] = {cnn_golden_0_output, cnn_golden_1_output, cnn_golden_2_output};
   int passed = 0;
   for (int sample = 0; sample < CNN_GOLDEN_COUNT; ++sample) {
      for (int i = 0; i < CNN_INPUT_BYTES; ++i) model_input->data.int8[i] = inputs[sample][i];
      const uint64_t begin = clint_getTime(BSP_CLINT);
      if (interpreter->Invoke() != kTfLiteOk) {
         MicroPrintf("FAIL Invoke sample=%d\n\r", sample); return 1;
      }
      const uint64_t ticks = clint_getTime(BSP_CLINT) - begin;
      int mismatch = 0;
      for (int i = 0; i < CNN_OUTPUT_CLASSES; ++i) mismatch |= (output->data.int8[i] != expected[sample][i]);
      passed += !mismatch;
      MicroPrintf("VECTOR %d actual=[%d,%d,%d] expected=[%d,%d,%d] ticks_hi=%u ticks_lo=%u\n\r",
         sample, output->data.int8[0], output->data.int8[1], output->data.int8[2],
         expected[sample][0], expected[sample][1], expected[sample][2],
         static_cast<unsigned>(ticks >> 32), static_cast<unsigned>(ticks));
   }
   MicroPrintf("ARENA used=%d CLINT_HZ=%u\n\r", static_cast<int>(interpreter->arena_used_bytes()), SYSTEM_CLINT_HZ);
   MicroPrintf("%s %d/%d\n\r", passed == CNN_GOLDEN_COUNT ? "PASS" : "FAIL", passed, CNN_GOLDEN_COUNT);
   return passed == CNN_GOLDEN_COUNT ? 0 : 1;
}
