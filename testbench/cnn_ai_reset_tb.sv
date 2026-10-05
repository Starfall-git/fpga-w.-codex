`timescale 1ns/1ps
module cnn_ai_reset_tb;
 reg clk=0,rst_n=0,memory_ready=0,reset_request=0,soc_reset=1;
 reg [1:0] quiescent=0;
 wire ai_reset,hardware_ready;
 always #5 clk=~clk;
 cnn_ai_reset dut(.*);
 task tick(input integer n);repeat(n)@(negedge clk);endtask
 initial begin
 tick(2);rst_n=1;tick(40);if(!ai_reset || hardware_ready)$fatal(1,"no DDR but released");
 memory_ready=1;tick(40);if(!ai_reset)$fatal(1,"pending DDR discarded");
 quiescent=3;tick(2);if(ai_reset || hardware_ready)$fatal(1,"release or readiness early");
 tick(40);if(ai_reset)$fatal(1,"Sapphire reset stretch retriggered");
 soc_reset=0;tick(2);if(!hardware_ready)$fatal(1,"no ready");
 // Debugger reset while a complete AI transaction is draining.
 quiescent=0;soc_reset=1;tick(2);if(!ai_reset||hardware_ready)$fatal(1,"debug reset missed");
 tick(45);if(!ai_reset)$fatal(1,"AI restarted before drain");
 quiescent=3;tick(2);if(ai_reset)$fatal(1,"drain never released");
 soc_reset=0;tick(2);if(!hardware_ready)$fatal(1,"did not recover");
 reset_request=1;#1;if(!ai_reset||hardware_ready)$fatal(1,"external request not immediate");
 tick(2);reset_request=0;tick(40);soc_reset=0;tick(2);
 memory_ready=0;#1;if(!ai_reset||hardware_ready)$fatal(1,"DDR loss unsafe");
 $display("PASS CNN AI reset: DDR prerequisite, full drain, Sapphire stretch, debugger/external reset, recovery");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
