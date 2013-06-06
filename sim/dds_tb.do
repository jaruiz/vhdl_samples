# assumed to run from /<project directory>/syn
# change the path to the libraries in the vmap commands to match your setup
# some unused modules' vcom calls have been commented out
vlib work

vcom -reportprogress 300 -work work ../hdl/fixed_pkg.vhdl
vcom -reportprogress 300 -work work ../hdl/dds.vhdl

vcom -reportprogress 300 -work work ../hdl/tb/txt_util.vhdl
vcom -reportprogress 300 -work work ../hdl/tb/dds_tb.vhdl

vsim -t ps work.dds_tb(behavior)
do ./dds_tb_wave.do
set PrefMain(font) {Courier 9 roman normal}
