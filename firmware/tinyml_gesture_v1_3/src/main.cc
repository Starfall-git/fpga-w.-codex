// v1.3 / 8: Fixed-input target test for the supplied Efinix TFLite Micro API.
// Prepared for integration; not yet cross-compiled or run on the board.
#include <stdint.h>
#include <string.h>
#include "intc.h"
#include "tensorflow/lite/micro/micro_error_reporter.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/micro/debug_log.h"
#include "tensorflow/lite/schema/schema_generated.h"
#include "model/gesture_classifier_int8_model_data.h"
#include "model/gesture_golden.h"

namespace {
// Provisional budget in external RAM; check linker map and measured usage.
// Do not infer this footprint from the desktop interpreter.
alignas(16) uint8_t arena[64 * 1024];
}

extern "C" void main() {
  IntcInitialize();
  static tflite::MicroErrorReporter reporter;
  const tflite::Model* model =
      tflite::GetModel(gesture_classifier_int8_model_data);
  if (model->version() != TFLITE_SCHEMA_VERSION) {
    MicroPrintf("FAIL gesture schema");
    return;
  }
  static tflite::MicroMutableOpResolver<3> resolver;
  if (resolver.AddConv2D() != kTfLiteOk ||
      resolver.AddReshape() != kTfLiteOk ||
      resolver.AddFullyConnected() != kTfLiteOk) {
    MicroPrintf("FAIL gesture resolver");
    return;
  }
  static tflite::MicroInterpreter interpreter(
      model, resolver, arena, sizeof(arena), &reporter);
  if (interpreter.AllocateTensors() != kTfLiteOk) {
    MicroPrintf("FAIL gesture allocation, reserved=%d", (int)sizeof(arena));
    return;
  }
  TfLiteTensor* input = interpreter.input(0);
  TfLiteTensor* output = interpreter.output(0);
  if (input->type != kTfLiteInt8 || input->bytes != 4096 ||
      output->type != kTfLiteInt8 || output->bytes != 6) {
    MicroPrintf("FAIL gesture tensor contract");
    return;
  }
  MicroPrintf("gesture arena_used_bytes=%d", (int)interpreter.arena_used_bytes());
  int mismatches = 0;
  for (int sample = 0; sample < kGestureGoldenCount; ++sample) {
    memcpy(input->data.int8, gesture_golden_input[sample], 4096);
    if (interpreter.Invoke() != kTfLiteOk) {
      MicroPrintf("FAIL gesture invoke sample=%d", sample);
      return;
    }
    for (int c = 0; c < 6; ++c) {
      const int actual = output->data.int8[c];
      const int expected = gesture_golden_output[sample][c];
      if (actual != expected) {
        ++mismatches;
        MicroPrintf("DIFF sample=%d class=%d actual=%d expected=%d",
                    sample, c, actual, expected);
      }
    }
  }
  MicroPrintf("gesture golden cases=%d mismatches=%d", kGestureGoldenCount,
              mismatches);
  MicroPrintf(mismatches == 0 ? "PASS gesture exact logits" :
                               "FAIL gesture exact logits");
  // No fabricated live result is published. Camera/UART integration is later.
}
