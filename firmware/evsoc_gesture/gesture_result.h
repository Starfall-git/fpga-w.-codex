#ifndef GESTURE_RESULT_H
#define GESTURE_RESULT_H
#include <stdint.h>
#include "io.h"
/* Base must come from the final generated BSP/address decoder, not a guessed
 * address. Single writer on hart 0. Coordinates are display pixels, x1/y1
 * exclusive, after geometry mapping. This API does not perform that mapping. */
static inline int gesture_publish_result(uintptr_t base, uint32_t frame,
    uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1,
    unsigned valid, unsigned cls)
{
    if (valid > 1 || cls > 2 || x0 > 4095 || y0 > 4095 ||
        x1 > 4095 || y1 > 4095 || (valid && (x0 >= x1 || y0 >= y1))) return -1;
    if (!(read_u32(base + 0x04) & 1u)) return 0;
    write_u32(frame, base + 0x08);
    write_u32((uint32_t)x0 | ((uint32_t)y0 << 16), base + 0x0c);
    write_u32((uint32_t)x1 | ((uint32_t)y1 << 16), base + 0x10);
    write_u32(valid | (cls << 1), base + 0x18);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    write_u32(1u, base + 0x14);
    return 1; /* queued, not proof that HDMI displayed it */
}
/* Stop starting new Invoke calls when disabled; an in-flight call may finish. */
static inline int gesture_inference_enabled(uintptr_t base)
{
    return (read_u32(base + 0x24) & 1u) != 0;
}
/* Call only after model allocation, accelerator and input pipeline are ready.
 * Reset clears this handshake; clearing it disables admission of new inference. */
static inline void gesture_set_ready(uintptr_t base, int ready)
{
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    write_u32(ready ? 0x47535452u : 0u, base + 0x28);
}
#endif

