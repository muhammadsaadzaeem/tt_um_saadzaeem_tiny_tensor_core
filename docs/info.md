# Tiny Tensor Core

## How it works

This project implements an INT8 2x2 systolic-array matrix multiplication accelerator. It uses four processing elements arranged as a 2x2 systolic array. Matrix values are loaded through an 8-bit byte-strobe command interface, then a control FSM feeds skewed operands into the array.

The accelerator computes matrix multiplication using INT8 operands and INT32 accumulation. After accumulation, the outputs pass through ReLU activation and programmable INT8 requantization using a right-shift scale factor. The design also includes a cycle-count performance counter that reports computation latency.

## How to test

The cocotb testbench loads randomized INT8 matrices, sets a requantization shift amount, starts computation, and reads back the quantized INT8 output values plus the cycle count.

The expected outputs are calculated using a Python golden model that performs:

1. 2x2 matrix multiplication
2. ReLU activation
3. right-shift requantization
4. saturation to INT8 range

The GitHub Actions flow verifies RTL simulation, gate-level simulation, GDS generation, precheck, and documentation.