// SPDX-License-Identifier: GPL-3.0-or-later
// terrain.c's to_camera() and project_xy(), as a combinational model for the
// fabric transform to be written against. This is the same integer
// arithmetic, including the 64-bit product the projection takes and the
// int16 clamp a wide vertex gets.
module vert_model(
    input signed [31:0] cam_x, cam_y, cam_z,
    input signed [31:0] sin_yaw, cos_yaw, sin_pitch, cos_pitch,
    input [15:0] gx, gz,
    input [7:0] alt,
    output signed [15:0] sx, sy,
    output [31:0] depth,
    output [1:0] state
);
    wire signed [31:0] wx = $signed({16'd0, gx}) * 32'sd160;
    wire signed [31:0] wy = ($signed({24'd0, alt}) * 32'sd2744) >>> 8;
    wire signed [31:0] wz = $signed({16'd0, gz}) * 32'sd160;
    wire signed [31:0] dx = wx - cam_x;
    wire signed [31:0] dy = wy - cam_y;
    wire signed [31:0] dz = wz - cam_z;
    wire signed [31:0] rz = (dx * sin_yaw + dz * cos_yaw) >>> 14;
    wire signed [31:0] x = (dx * cos_yaw - dz * sin_yaw) >>> 14;
    wire signed [31:0] y = (dy * cos_pitch + rz * sin_pitch) >>> 14;
    wire signed [31:0] z = (rz * cos_pitch - dy * sin_pitch) >>> 14;
    wire front = z >= 32'sd128;
    // C's (1 << 30) / z is an int division, so this is 32 bits wide.
    wire signed [31:0] inv = front ? (32'sd1 << 30) / z : 32'sd0;
    // x * inv is 64 bits in C, and the >> 18 result is cast to int32.
    wire signed [63:0] xinv = {{32{x[31]}}, x} * {{32{inv[31]}}, inv};
    wire signed [63:0] yinv = {{32{y[31]}}, y} * {{32{inv[31]}}, inv};
    wire signed [31:0] xoff = (xinv >>> 18);
    wire signed [31:0] yoff = (yinv >>> 18);
    wire signed [31:0] sxr = 32'sd2560 + xoff;
    wire signed [31:0] syr = 32'sd1440 - yoff;
    wire wide = front && (sxr > 32'sd32767 || sxr < -32'sd32768 ||
                          syr > 32'sd32767 || syr < -32'sd32768);
    wire signed [15:0] sxc = sxr > 32'sd32767 ? 16'sd32767 :
                             sxr < -32'sd32768 ? -16'sd32768 : sxr[15:0];
    wire signed [15:0] syc = syr > 32'sd32767 ? 16'sd32767 :
                             syr < -32'sd32768 ? -16'sd32768 : syr[15:0];
    assign sx = front ? sxc : 16'sd0;
    assign sy = front ? syc : 16'sd0;
    assign depth = front ? inv : 32'd0;
    assign state = !front ? 2'd1 : wide ? 2'd2 : 2'd0;
endmodule
