from pathlib import Path
import random, subprocess, os
r=Path(__file__).resolve().parents[1]; sim=r/'sim'/os.environ.get('SIM_TAG','')
sim.mkdir(parents=True,exist_ok=True)
rng=random.Random(520)
W,H=1280,int(os.environ.get('TEST_HEIGHT','16'))
stim=[];expected=[]
for mode in range(4):
 raw=[];gray=[]
 for y in range(H):
  rr=[];gg=[]
  for x in range(W):
   if mode==0: rgb=rng.randrange(1<<24)
   else:
    g=max(0,min(255,(35 if x<W//2 else 180)+rng.randint(-9,9)))
    if rng.randrange(31)==0:g=rng.choice([0,255])
    rgb=(g<<16)|(g<<8)|g
   rr.append(rgb);gg.append((((rgb>>16)*77)+((rgb>>8&255)*150)+((rgb&255)*29)+128)>>8)
  raw.append(rr);gray.append(gg)
 med=[[gray[y][x] if y<2 or x<2 else sorted(gray[j][k] for j in range(y-2,y+1) for k in range(x-2,x+1))[4] for x in range(W)]for y in range(H)]
 for y in range(H):
  for x in range(0,W,4):
   din=out=0
   for k in range(4):
    xx=x+k;din=(din<<24)|raw[y][xx]
    if mode==0:rgb=raw[y][xx]
    elif mode==1:rgb=gray[y][xx]*0x010101
    elif mode==2:rgb=med[y][xx]*0x010101
    else:
     edge=False
     if y>=2 and xx>=2:
      a=[med[j][q] for j in range(y-2,y+1) for q in range(xx-2,xx+1)]
      mag=abs(a[2]+2*a[5]+a[8]-a[0]-2*a[3]-a[6])+abs(a[6]+2*a[7]+a[8]-a[0]-2*a[1]-a[2])
      thr=112 if a[4]<64 else 88 if a[4]<128 else 64
      edge=mag>=thr
     rgb=0xffffff if edge else 0
    out=(out<<24)|rgb
   sof=int(y==0 and x==0);eol=int(x==W-4)
   # Change the requested mode in the second half of a frame; output must
   # remain in the latched mode until the next SOF.
   request=mode if y<H//2 else (mode+1)%4
   stim.append(f'{1:x}{sof:x}{eol:x}{request:x}{din:024x}')
   expected.append(f'{sof:x}{eol:x}{out:024x}')
   # Burst bubbles exercise valid qualification and bank addresses.
   if x%28==0:stim.append(f'000{request:x}'+24*'0')
  stim.extend([f'000{request:x}'+24*'0']*21)
(sim/'input.hex').write_text('\n'.join(stim))
(sim/'expected.hex').write_text('\n'.join(expected))
tb=f'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0;reg [111:0] token=0;
wire ov,os,ol;wire [95:0] od;
reg [111:0] ins[0:{len(stim)-1}];reg [103:0] exp[0:{len(expected)-1}];
integer i,n=0,errors=0;
image_modes4 dut(.I_clk(clk),.I_rst_n(rst),.I_mode(token[97:96]),
.I_tvalid(token[108]),.I_tuser(token[104]),.I_tlast(token[100]),.I_tdata(token[95:0]),
.I_tready(),.O_tready(1'b1),.O_tvalid(ov),.O_tuser(os),.O_tlast(ol),.O_tdata(od));
always @(negedge clk) if(rst&&ov) begin
 if(n>={len(expected)}) $fatal(1,"Too many outputs");
 if({{os,ol,od}} !== {{exp[n][100],exp[n][96],exp[n][95:0]}}) begin
  if(errors<8)$display("Mismatch %0d got=%h expected=%h",n,od,exp[n][95:0]);
  errors=errors+1;
 end
 n=n+1;
end
initial begin
 $readmemh("input.hex",ins);$readmemh("expected.hex",exp);
 repeat(5)@(posedge clk);#1;rst=1;
 for(i=0;i<{len(stim)};i=i+1) begin @(posedge clk);#1;token=ins[i];end
 @(posedge clk);#1;token=0;
 repeat(40)@(posedge clk);
 if(errors||n!={len(expected)})$fatal(1,"FAIL errors=%0d tokens=%0d",errors,n);
 $display("PASS four modes: %0d groups / %0d pixels",n,n*4);$finish;
end
endmodule
'''
(sim/'tb.v').write_text(tb)
iverilog=Path('E:/fpga/_tools/iverilog/bin')
subprocess.run([str(iverilog/'iverilog.exe'),'-g2012','-s','tb','-o','test.vvp','tb.v',str(r/'sim/ph1p_eram_sim_model.v'),str(r/'rtl/image_modes4.v'),str(r/'rtl/window4.v')],cwd=sim,check=True)
p=subprocess.run([str(iverilog/'vvp.exe'),'test.vvp'],cwd=sim,capture_output=True,text=True)
print(p.stdout);(sim/'verification.log').write_text(p.stdout)
raise SystemExit(p.returncode)
