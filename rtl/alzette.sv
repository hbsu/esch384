// alzette.sv
// Purpose : Alzette ARX-box (SPARKLE spec Alg. 2.4). Four rounds of
//           add / rotate / xor on a 64-bit (x, y) pair with round
//           constant c. All adds are mod 2^32, rotations are right.
// Ports   : x_in, y_in [31:0] - input word pair
//           c          [31:0] - round constant (port, so one instance
//                               can be shared in an area-optimized design)
//           x_out, y_out [31:0] - output word pair (u, v)
// Latency : 0 cycles (purely combinational)
module alzette (
    input  logic [31:0] x_in,
    input  logic [31:0] y_in,
    input  logic [31:0] c,
    output logic [31:0] x_out,
    output logic [31:0] y_out
);

    // Round 1: rotations 31, 24
    logic [31:0] x1a, y1, x1;
    assign x1a = x_in + {y_in[30:0], y_in[31]};      // y >>> 31
    assign y1  = y_in ^ {x1a[23:0], x1a[31:24]};      // x >>> 24
    assign x1  = x1a ^ c;

    // Round 2: rotations 17, 17
    logic [31:0] x2a, y2, x2;
    assign x2a = x1 + {y1[16:0], y1[31:17]};          // y >>> 17
    assign y2  = y1 ^ {x2a[16:0], x2a[31:17]};        // x >>> 17
    assign x2  = x2a ^ c;

    // Round 3: rotations 0, 31
    logic [31:0] x3a, y3, x3;
    assign x3a = x2 + y2;
    assign y3  = y2 ^ {x3a[30:0], x3a[31]};           // x >>> 31
    assign x3  = x3a ^ c;

    // Round 4: rotations 24, 16
    logic [31:0] x4a, y4, x4;
    assign x4a = x3 + {y3[23:0], y3[31:24]};          // y >>> 24
    assign y4  = y3 ^ {x4a[15:0], x4a[31:16]};        // x >>> 16
    assign x4  = x4a ^ c;

    assign x_out = x4;
    assign y_out = y4;

endmodule
