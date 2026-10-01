"""v1.0 / 1: Gesture CNN candidates and reproducible arithmetic budgets.

No trained weights are included. TensorFlow is imported only by build_model().
Budgets exclude scheduling, requantization, pooling arithmetic and TFLM scratch.
"""
import argparse
import json


def architecture(size=64, classes=4, depthwise=True):
    """v1.0 / 2: NHWC gray input; SAME strides; explicit average pool head."""
    if size < 16 or size % 16 or classes < 2:
        raise ValueError("size must be a positive multiple of 16; classes >= 2")
    layers = [{"name": "stem", "op": "conv", "kernel": 3,
               "stride": 2, "channels": 8}]
    for index, channels in enumerate((16, 32, 48), 1):
        if depthwise:
            layers.append({"name": f"dw{index}", "op": "depthwise",
                           "kernel": 3, "stride": 2})
            layers.append({"name": f"pw{index}", "op": "conv",
                           "kernel": 1, "stride": 1, "channels": channels})
        else:
            layers.append({"name": f"conv{index}", "op": "conv",
                           "kernel": 3, "stride": 2, "channels": channels})
    layers.extend([{"name": "pool", "op": "pool"},
                   {"name": "logits", "op": "dense", "channels": classes}])
    return layers


def budget(size=64, classes=4, depthwise=True):
    h = w = size
    c = 1
    rows = []
    for layer in architecture(size, classes, depthwise):
        input_bytes = h * w * c
        op = layer["op"]
        weights = biases = macs = 0
        if op in ("conv", "depthwise"):
            stride, kernel = layer["stride"], layer["kernel"]
            h, w = (h + stride - 1) // stride, (w + stride - 1) // stride
            out_c = c if op == "depthwise" else layer["channels"]
            weights = kernel * kernel * c * (1 if op == "depthwise" else out_c)
            biases = out_c
            macs = h * w * weights
            c = out_c
        elif op == "pool":
            h = w = 1
        else:
            weights = c * layer["channels"]
            biases = layer["channels"]
            macs = weights
            c = biases
        rows.append(dict(name=layer["name"], op=op, output=[h, w, c],
                         weights=weights, biases=biases, macs=macs,
                         output_int8_bytes=h*w*c,
                         adjacent_io_int8_bytes=input_bytes+h*w*c))
    return dict(version="v1.0", input=[1, size, size, 1], classes=classes,
                variant="depthwise" if depthwise else "regular",
                layers=rows, macs=sum(r["macs"] for r in rows),
                trainable_parameters=sum(r["weights"]+r["biases"] for r in rows),
                int8_weights_int32_bias_bytes=sum(r["weights"]+4*r["biases"] for r in rows),
                max_adjacent_io_bytes=max(r["adjacent_io_int8_bytes"] for r in rows),
                caveat="Not TFLite file size, tensor arena size, FPGA area or measured latency")


def build_model(size=64, classes=4, depthwise=True):
    """v1.0 / 3: Untrained Keras model; train with from_logits=True.

    Input contract: exact gray ROI pixels converted to float32 / 255.
    Conversion must use real representative images and full INT8 operators.
    """
    specification = architecture(size, classes, depthwise)
    import tensorflow as tf
    inputs = tf.keras.Input(shape=(size, size, 1), batch_size=1, name="gray_roi")
    x = inputs
    spatial = size
    for layer in specification:
        op = layer["op"]
        if op in ("conv", "depthwise"):
            common = dict(kernel_size=layer["kernel"], strides=layer["stride"],
                          padding="same", activation="relu", use_bias=True,
                          name=layer["name"])
            if op == "depthwise":
                x = tf.keras.layers.DepthwiseConv2D(**common)(x)
            else:
                x = tf.keras.layers.Conv2D(layer["channels"], **common)(x)
            spatial = (spatial + layer["stride"] - 1) // layer["stride"]
        elif op == "pool":
            x = tf.keras.layers.AveragePooling2D(pool_size=spatial, name="pool")(x)
            x = tf.keras.layers.Flatten(name="flatten")(x)
        else:
            x = tf.keras.layers.Dense(layer["channels"], name="logits")(x)
    return tf.keras.Model(inputs, x, name="gesture_v1_0")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, default=64)
    parser.add_argument("--classes", type=int, default=4)
    parser.add_argument("--regular", action="store_true")
    args = parser.parse_args()
    print(json.dumps(budget(args.size, args.classes, not args.regular), indent=2))
