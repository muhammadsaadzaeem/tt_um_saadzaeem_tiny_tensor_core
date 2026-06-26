<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project implements a 2x2 INT8 systolic-array matrix multiplication accelerator. Matrix values are loaded through an 8-bit byte-serial input interface. A small control FSM feeds skewed operands into four processing elements, computes the matrix product, and streams the 32-bit results back over the 8-bit output port.

## How to test

The cocotb testbench loads matrices A = [[1, 2], [3, 4]] and B = [[5, 6], [7, 8]], starts computation, then reads back the result matrix. The expected output is C = [[19, 22], [43, 50]].

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
