// Static bring-up only: vendor DDR3 Sapphire BSP, no live video integration.
#include <stdint.h>
#include <string.h>
#include "cnn_gesture_data.h"
#include "tensorflow/lite/micro/micro_error_reporter.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/micro/debug_log.h"
#include "tensorflow/lite/schema/schema_generated.h"
#include "bsp.h"

// A test allocation ceiling, NOT a measured minimum or a video-system map.
#ifndef CNN_ARENA_BYTES
#define CNN_ARENA_BYTES (256 * 1024)
#endif
alignas(16) static uint8_t arena[CNN_ARENA_BYTES];

static uint64_t cycles() {
  uint32_t hi, lo, again;
  do {
    asm volatile("rdcycleh %0" : "=r"(hi));
    asm volatile("rdcycle %0" : "=r"(lo));
    asm volatile("rdcycleh %0" : "=r"(again));
  } while (hi != again);
  return (static_cast<uint64_t>(hi) << 32) | lo;
}

static int argmax(const int8_t* logits) {
  int best = 0;
  for (int i = 1; i < CNN_OUTPUT_CLASSES; ++i)
    if (logits[i] > logits[best]) best = i;
  return best;
}

extern "C" int main() {
  bsp_init();
  uint32_t hart;
  asm volatile("csrr %0, mhartid" : "=r"(hart));
  if (hart != 0) return 1;  // Vendor acceleration settings contain only core 0.
  MicroPrintf("CNN_STATIC software kernels, no camera / no video DDR map\r\n");
  MicroPrintf("MODEL sha256=%s\r\n", CNN_MODEL_SHA256);
  const tflite::Model* model = tflite::GetModel(cnn_model_data);
  if (model->version() != TFLITE_SCHEMA_VERSION) {
    MicroPrintf("FAIL schema\r\n"); return 1;
  }
  tflite::MicroErrorReporter reporter;
  tflite::MicroMutableOpResolver<5> resolver;
  if (resolver.AddConv2D() != kTfLiteOk || resolver.AddMaxPool2D() != kTfLiteOk ||
      resolver.AddAveragePool2D() != kTfLiteOk || resolver.AddReshape() != kTfLiteOk ||
      resolver.AddFullyConnected() != kTfLiteOk) {
    MicroPrintf("FAIL resolver\r\n"); return 1;
  }
  tflite::MicroInterpreter interpreter(model, resolver, arena, sizeof(arena), &reporter);
  if (interpreter.AllocateTensors() != kTfLiteOk) {
    MicroPrintf("FAIL AllocateTensors ceiling=%d\r\n", static_cast<int>(sizeof(arena))); return 1;
  }
  TfLiteTensor* input = interpreter.input(0);
  TfLiteTensor* output = interpreter.output(0);
  if (interpreter.inputs_size() != 1 || interpreter.outputs_size() != 1 ||
      input->type != kTfLiteInt8 || output->type != kTfLiteInt8 ||
      input->bytes != CNN_INPUT_BYTES || output->bytes != CNN_OUTPUT_CLASSES ||
      input->dims->size != 4 || input->dims->data[0] != 1 ||
      input->dims->data[1] != 64 || input->dims->data[2] != 64 || input->dims->data[3] != 1 ||
      output->dims->size != 2 || output->dims->data[0] != 1 || output->dims->data[1] != 3 ||
      input->params.scale != cnn_input_scale || input->params.zero_point != cnn_input_zero_point ||
      output->params.scale != cnn_output_scale || output->params.zero_point != cnn_output_zero_point) {
    MicroPrintf("FAIL tensor contract\r\n"); return 1;
  }
  MicroPrintf("ARENA used=%d ceiling=%d\r\n", static_cast<int>(interpreter.arena_used_bytes()),
              static_cast<int>(sizeof(arena)));
  const int8_t* inputs[] = {cnn_golden_0_input, cnn_golden_1_input, cnn_golden_2_input};
  const int8_t* expected[] = {cnn_golden_0_output, cnn_golden_1_output, cnn_golden_2_output};
  int exact_total = 0;
  for (int sample = 0; sample < CNN_GOLDEN_COUNT; ++sample) {
    memcpy(input->data.int8, inputs[sample], CNN_INPUT_BYTES);
    const uint64_t begin = cycles();
    if (interpreter.Invoke() != kTfLiteOk) {
      MicroPrintf("FAIL invoke sample=%d\r\n", sample); return 1;
    }
    const uint64_t elapsed = cycles() - begin;
    int max_error = 0;
    for (int i = 0; i < CNN_OUTPUT_CLASSES; ++i) {
      int error = static_cast<int>(output->data.int8[i]) - expected[sample][i];
      if (error < 0) error = -error;
      if (error > max_error) max_error = error;
    }
    exact_total += max_error == 0;
    MicroPrintf("VECTOR %d actual=[%d,%d,%d] expected=[%d,%d,%d] max_abs=%d pred=%d ref=%d cycles_hi=%u cycles_lo=%u\r\n",
      sample, output->data.int8[0], output->data.int8[1], output->data.int8[2],
      expected[sample][0], expected[sample][1], expected[sample][2], max_error,
      argmax(output->data.int8), argmax(expected[sample]),
      static_cast<unsigned>(elapsed >> 32), static_cast<unsigned>(elapsed));
  }
  MicroPrintf("CNN_STATIC exact_vectors=%d/%d %s\r\n", exact_total, CNN_GOLDEN_COUNT,
              exact_total == CNN_GOLDEN_COUNT ? "PASS" : "MISMATCH");
  return exact_total == CNN_GOLDEN_COUNT ? 0 : 1;
}
