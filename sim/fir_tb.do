# assumed to run from /<project directory>/sim
# 
vlib work

vcom -reportprogress 300 -work work ../hdl/tb/txt_util.vhdl
vcom -reportprogress 300 -work work ../hdl/fixed_pkg.vhdl
vcom -reportprogress 300 -work work ../hdl/fir.vhdl

vcom -reportprogress 300 -work work ../hdl/tb/fir_tb.vhdl

vsim -t ps work.fir_tb(tb0)
do ./fir_tb_wave.do
set PrefMain(font) {Courier 9 roman normal}
