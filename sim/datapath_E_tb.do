# assumed to run from /<project directory>/syn
# change the path to the libraries in the vmap commands to match your setup
# some unused modules' vcom calls have been commented out
vlib work

vcom -reportprogress 300 -work work ../hdl/datapath_E.vhdl

vcom -reportprogress 300 -work work ../hdl/tb/txt_util.vhdl
vcom -reportprogress 300 -work work ../hdl/tb/datapath_E_tb.vhdl

vsim -t ps work.datapath_E_tb(tb0)
do ./datapath_E_tb_wave.do
set PrefMain(font) {Courier 9 roman normal}
