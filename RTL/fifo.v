module fifo(clk,rst,in,out,wren,rden,empty,full);
  input            clk;
  input            rst;
  input      [7:0] in;
  input            wren,rden;
  output reg [7:0] out;
  output reg       empty,full;

  reg [2:0] wr_ptr,rd_ptr;
  reg [7:0] data [0:7];
  reg       wrap_rd,wrap_wr;

  always@(posedge clk or posedge rst) begin
    if(rst)begin
      wr_ptr  <= 3'b0;
      wrap_wr <= 1'b0;
      rd_ptr  <= 3'b0;
      wrap_rd <= 1'b0;
      out     <= 8'b0;      
    end
    else begin
      if(wren==1'b1 && full==1'b0)begin
        data[wr_ptr] <= in;
        if(wr_ptr==3'd7)begin
          wr_ptr  <= 3'b0;
          wrap_wr <= ~wrap_wr;
        end
        else begin
          wr_ptr <= wr_ptr + 1'b1;
        end
      end

      if(rden==1'b1 && empty==1'b0)begin
        out <= data[rd_ptr];
        if(rd_ptr==3'd7)begin
          rd_ptr  <= 3'b0;
          wrap_rd <= ~wrap_rd;
        end
        else begin
          rd_ptr <= rd_ptr + 1'b1;
        end
      end
    end
  end // posedge

   always@(*) begin
    if(rd_ptr==wr_ptr)begin
      empty = ~(wrap_wr ^ wrap_rd);
      full  =  (wrap_rd ^ wrap_wr);
    end
    else begin
      full  = 1'b0;
      empty = 1'b0;
    end
  end
endmodule
